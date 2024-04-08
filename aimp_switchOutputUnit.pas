{**********************************************}
{*                                            *}
{*           Plugin for AIMP v5.30            *}
{* Switches between output devices via hotkey *}
{*                                            *}
{*            (c) Artem Izmaylov              *}
{*                 2023-2024                  *}
{*                www.aimp.ru                 *}
{*                                            *}
{**********************************************}

unit aimp_switchOutputUnit;

{$I aimp_switchOutput.inc}

interface

uses
  Windows,
  apiActions,
  apiCore,
  apiGUI,
  apiMessages,
  apiMUI,
  apiObjects,
  apiPlayer,
  apiPlugin;

type

  { TSwitchOutputPlugin }

  TSwitchOutputPlugin = class(TInterfacedObject,
    IAIMPActionEvent,
    IAIMPExternalSettingsDialog,
    IAIMPPlugin)
  strict private const
    ActionID = 'aimp.switchoutput.action.toggle';
  strict private
    FAction: IAIMPAction;
    FCore: IAIMPCore;
    FDeviceName1: IAIMPString;
    FDeviceName2: IAIMPString;

    function GetPlayerProps(ACore: IAIMPCore; out AProps: IAIMPPropertyList): Boolean;
    function IsRequiredApiAvailable(ACore: IAIMPCore): Boolean;
    function MakeString(const S: UnicodeString): IAIMPString;
  public
    // IAIMPPlugin
    procedure Finalize; virtual; stdcall;
    function Initialize(Core: IAIMPCore): HRESULT; stdcall;
    function InfoGetCategories: Cardinal; stdcall;
    function InfoGet(Index: Integer): PWideChar; stdcall;
    procedure SystemNotification(NotifyID: Integer; Data: IUnknown); virtual; stdcall;
    // IAIMPExternalSettingsDialog
    procedure Show(ParentWindow: HWND); stdcall;
    // IAIMPActionEvent
    procedure OnExecute(Data: IUnknown); stdcall;
  end;

function AIMPPluginGetHeader(out Header: IAIMPPlugin): HRESULT; stdcall;
implementation

function AIMPPluginGetHeader(out Header: IAIMPPlugin): HRESULT; stdcall;
begin
  try
    Header := TSwitchOutputPlugin.Create;
    Result := S_OK;
  except
    Result := E_UNEXPECTED;
  end;
end;

{ TSwitchOutputPlugin }

procedure TSwitchOutputPlugin.Finalize;
begin
  FAction := nil;
  FCore := nil;
end;

function TSwitchOutputPlugin.Initialize(Core: IAIMPCore): HRESULT;
var
  LConfig: IAIMPServiceConfig;
begin
  Result := E_FAIL;
  if IsRequiredApiAvailable(Core) then
  begin
    FCore := Core;
    if Succeeded(FCore.CreateObject(IID_IAIMPAction, FAction)) then
    begin
      FAction.SetValueAsObject(AIMP_ACTION_PROPID_ID, MakeString(ActionID));
      FAction.SetValueAsObject(AIMP_ACTION_PROPID_EVENT, Self);
      FCore.RegisterExtension(IAIMPServiceActionManager, FAction);
    end;
    if Succeeded(FCore.QueryInterface(IAIMPServiceConfig, LConfig)) then
    begin
      LConfig.GetValueAsString(MakeString('SwitchOutput\Device1'), FDeviceName1);
      LConfig.GetValueAsString(MakeString('SwitchOutput\Device2'), FDeviceName2);
    end;
    Result := S_OK;
  end;
end;

function TSwitchOutputPlugin.GetPlayerProps(ACore: IAIMPCore; out AProps: IAIMPPropertyList): Boolean;
var
  LService: IAIMPServicePlayer;
begin
  Result :=
    Succeeded(ACore.QueryInterface(IAIMPServicePlayer, LService)) and
    Succeeded(LService.QueryInterface(IAIMPPropertyList, AProps));
end;

function TSwitchOutputPlugin.InfoGet(Index: Integer): PWideChar;
begin
  case Index of
    AIMP_PLUGIN_INFO_NAME:
      Result := 'SwitchOutput v1.0';
    AIMP_PLUGIN_INFO_AUTHOR:
      Result := 'Artem Izmaylov';
    AIMP_PLUGIN_INFO_SHORT_DESCRIPTION:
      Result := 'Switches between output devices via hotkey';
  else
    Result := '';
  end;
end;

function TSwitchOutputPlugin.InfoGetCategories: Cardinal;
begin
  Result := AIMP_PLUGIN_CATEGORY_ADDONS;
end;

function TSwitchOutputPlugin.IsRequiredApiAvailable(ACore: IAIMPCore): Boolean;
var
  LList: IAIMPPropertyList;
  LTemp: IAIMPString;
begin
  Result := GetPlayerProps(ACore, LList) and
    Succeeded(LList.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPString, LTemp));
end;

function TSwitchOutputPlugin.MakeString(const S: UnicodeString): IAIMPString;
begin
  if Succeeded(FCore.CreateObject(IAIMPString, Result)) then
    Result.SetData(PWideChar(S), Length(S))
  else
    Result := nil;
end;

procedure TSwitchOutputPlugin.OnExecute(Data: IInterface);
var
  LCompareResult: Integer;
  LDevice: IAIMPString;
  LMessage: IAIMPString;
  LProps: IAIMPPropertyList;
  LServiceMsg: IAIMPServiceMessageDispatcher;
  LServiceMui: IAIMPServiceMUI;
  LWinHandle: HWND;
begin
  // Show the Settings Dialog if devices are not specified
  if (FDeviceName1 = nil) or (FDeviceName1.GetLength = 0) or
     (FDeviceName2 = nil) or (FDeviceName2.GetLength = 0) then
  begin
    if FCore.QueryInterface(IAIMPServiceMessageDispatcher, LServiceMsg) = S_OK then
    begin
      if LServiceMsg.Send(AIMP_MSG_PROPERTY_HWND, AIMP_MSG_PROPVALUE_GET, @LWinHandle) = S_OK then
        Show(LWinHandle);
    end;
    Exit;
  end;

  // Toggle the outputs
  if GetPlayerProps(FCore, LProps) then
  begin
    if LProps.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPString, LDevice) = S_OK then
    begin
      if (LDevice.Compare(FDeviceName1, LCompareResult, True) = S_OK) and (LCompareResult = 0) then
        LDevice := FDeviceName2
      else
        LDevice := FDeviceName1;

      // Set and notify
      if LProps.SetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, LDevice) = S_OK then
      begin
        // Post the notification
        LMessage := nil;
        if FCore.QueryInterface(IAIMPServiceMUI, LServiceMui) = S_OK then
          LServiceMui.GetValue(MakeString('OptionsSoundOutFrame\L2'), LMessage);
        if LMessage = nil then
          LMessage := MakeString('Output:');
        LMessage.Add2(' ', 1);
        LMessage.Add(LDevice);
        if FCore.QueryInterface(IAIMPServiceMessageDispatcher, LServiceMsg) = S_OK then
          LServiceMsg.Send(AIMP_MSG_CMD_SHOW_NOTIFICATION, 0, LMessage.GetData);
      end;
    end;
  end;
end;

procedure TSwitchOutputPlugin.Show(ParentWindow: HWND);
const
  FormHeight = 200;
  FormWidth = 400;
var
  LForm: IAIMPUIForm;
  LService: IAIMPServiceUI;
  LServiceMUI: IAIMPServiceMUI;

  procedure AddLabel(const ACaption: IAIMPString);
  var
    LLabel: IAIMPUILabel;
  begin
    if Succeeded(LService.CreateControl(LForm, LForm, nil, nil, IAIMPUILabel, LLabel)) then
    begin
      LLabel.SetValueAsInt32(AIMPUI_LABEL_PROPID_AUTOSIZE, 1);
      //LLabel.SetValueAsInt32(AIMPUI_LABEL_PROPID_WORDWRAP, 1);
      LLabel.SetValueAsObject(AIMPUI_LABEL_PROPID_TEXT, ACaption);
      LLabel.SetPlacement(TAIMPUIControlPlacement.Create(ualTop, 0, TRect.Create(3, 3, 3, 0)));
    end;
  end;

  function AddComboBox(AList: IAIMPObjectList; ACurrentValue: IAIMPString): IAIMPUIComboBox;
  begin
    if Succeeded(LService.CreateControl(LForm, LForm, nil, nil, IAIMPUIComboBox, Result)) then
    begin
      if AList <> nil then
        Result.Add2(AList);
      Result.SetValueAsObject(AIMPUI_COMBOBOX_PROPID_TEXT, ACurrentValue);
      Result.SetValueAsInt32(AIMPUI_COMBOBOX_PROPID_AUTOCOMPLETE, 1);
      Result.SetPlacement(TAIMPUIControlPlacement.Create(ualTop, 0));
    end;
  end;

  function Localize(const ID: string): IAIMPString;
  begin
    if Failed(LServiceMUI.GetValue(MakeString('Common\aimp.switchoutput.dlg.' + ID), Result)) then
      Result := nil;
  end;

var
  LButton: IAIMPUIButton;
  LConfig: IAIMPServiceConfig;
  LDevice1: IAIMPUIComboBox;
  LDevice2: IAIMPUIComboBox;
  LDevices: IAIMPObjectList;
  LFormPos: TRect;
  LProps: IAIMPPropertyList;
begin
  if Succeeded(FCore.QueryInterface(IAIMPServiceUI, LService)) and
     Succeeded(FCore.QueryInterface(IAIMPServiceMUI, LServiceMUI)) then
  begin
    LDevices := nil;
    if GetPlayerProps(FCore, LProps) then
    begin
      if Failed(LProps.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPObjectList, LDevices)) then
        LDevices := nil;
    end;

    if Succeeded(LService.CreateForm(ParentWindow, 0, nil, nil, LForm)) then
    try
      GetWindowRect(ParentWindow, LFormPos);
      LFormPos.Left := (LFormPos.Left + LFormPos.Right - FormWidth) div 2;
      LFormPos.Width := FormWidth;
      LFormPos.Top := (LFormPos.Top + LFormPos.Bottom - FormHeight) div 2;
      LFormPos.Height := FormHeight;
      LForm.SetPlacement(TAIMPUIControlPlacement.Create(LFormPos));
      LForm.SetValueAsObject(AIMPUI_FORM_PROPID_CAPTION, Localize('Settings'));
      LForm.SetValueAsInt32(AIMPUI_FORM_PROPID_BORDERSTYLE, AIMPUI_FLAGS_BORDERSTYLE_DIALOG);
      LForm.SetValueAsInt32(AIMPUI_FORM_PROPID_PADDING, 8);

      AddLabel(Localize('device1'));
      LDevice1 := AddComboBox(LDevices, FDeviceName1);
      AddLabel(Localize('device2'));
      LDevice2 := AddComboBox(LDevices, FDeviceName2);
      AddLabel(Localize('hotkeyHint'));

      if Succeeded(LService.CreateControl(LForm, LForm, nil, nil, IAIMPUIButton, LButton)) then
      begin
        LButton.SetValueAsInt32(AIMPUI_BUTTON_PROPID_MODALRESULT, idOK);
        LButton.SetValueAsObject(AIMPUI_BUTTON_PROPID_CAPTION, Localize('ok'));
        LButton.SetPlacement(TAIMPUIControlPlacement.Create(ualBottom, 25, TRect.Create(280, 0, 0, 0)));
      end;

      if LForm.ShowModal = idOK then
      begin
        LDevice1.GetValueAsObject(AIMPUI_COMBOBOX_PROPID_TEXT, IAIMPString, FDeviceName1);
        LDevice2.GetValueAsObject(AIMPUI_COMBOBOX_PROPID_TEXT, IAIMPString, FDeviceName2);
        if Succeeded(FCore.QueryInterface(IAIMPServiceConfig, LConfig)) then
        begin
          LConfig.SetValueAsString(MakeString('SwitchOutput\Device1'), FDeviceName1);
          LConfig.SetValueAsString(MakeString('SwitchOutput\Device2'), FDeviceName2);
        end;
      end;
    finally
      LForm.Release(True);
    end;
  end;
end;

procedure TSwitchOutputPlugin.SystemNotification(NotifyID: Integer; Data: IInterface);
begin
  // do nothing
end;

end.
