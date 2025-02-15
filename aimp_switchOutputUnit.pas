////////////////////////////////////////////////////////////////////////////////
//
//  Project:   SwitchOutput plugin
//
//  Target:    AIMP v5.40 build 2400
//
//  Purpose:   Switches between output devices via hotkey
//
//  Author:    Artem Izmaylov
//             © 2023-2025
//             www.aimp.ru
//
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
  apiOptions,
  apiPlayer,
  apiPlugin,
  apiWrappers;

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
    FDeviceName1: IAIMPString;
    FDeviceName2: IAIMPString;

    function GetPlayerProps(ACore: IAIMPCore; out AProps: IAIMPPropertyList): Boolean;
    function IsDeviceAvailable(const ADevice: IAIMPString): Boolean;
    function IsRequiredApiAvailable(ACore: IAIMPCore): Boolean;
    procedure PostNotification(const AText: string); overload;
    procedure PostNotification(const ATextId: string; const ADevice: IAIMPString); overload;
  public
    // IAIMPPlugin
    procedure Finalize; virtual; stdcall;
    function Initialize(Core: IAIMPCore): HRESULT; stdcall;
    function InfoGetCategories: Cardinal; stdcall;
    function InfoGet(Index: Integer): PChar; stdcall;
    procedure SystemNotification(NotifyID: Integer; Data: IUnknown); virtual; stdcall;
    // IAIMPExternalSettingsDialog
    procedure Show(ParentWindow: HWND); stdcall;
    // IAIMPActionEvent
    procedure OnExecute(Data: IUnknown); stdcall;
  end;

  { TSwitchOutputOpenHotkeysAction }

  TSwitchOutputOpenHotkeysAction = class(TInterfacedObject, IAIMPUIChangeEvents)
  strict private
    FCore: IAIMPCore;
    FForm: IAIMPUIForm;
  public
    class function CreateIfAvailable(ACore: IAIMPCore; AForm: IAIMPUIForm): IAIMPUIChangeEvents;
    // IAIMPUIChangeEvents
    procedure OnChanged(Sender: IInterface); stdcall;
  end;

function AIMPPluginGetHeader(out Header: IAIMPPlugin): HRESULT; stdcall;
implementation

uses
  SysUtils;

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
  TAIMPAPIWrappers.Finalize;
end;

function TSwitchOutputPlugin.Initialize(Core: IAIMPCore): HRESULT;
var
  LConfig: IAIMPServiceConfig;
begin
  Result := E_FAIL;
  if IsRequiredApiAvailable(Core) then
  begin
    TAIMPAPIWrappers.Initialize(Core);
    if Succeeded(Core.CreateObject(IID_IAIMPAction, FAction)) then
    begin
      FAction.SetValueAsObject(AIMP_ACTION_PROPID_ID, MakeString(ActionID));
      FAction.SetValueAsObject(AIMP_ACTION_PROPID_EVENT, Self);
      Core.RegisterExtension(IAIMPServiceActionManager, FAction);
    end;
    if Succeeded(Core.QueryInterface(IAIMPServiceConfig, LConfig)) then
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

function TSwitchOutputPlugin.InfoGet(Index: Integer): PChar;
begin
  case Index of
    AIMP_PLUGIN_INFO_NAME:
      Result := 'SwitchOutput v1.0.1';
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

function TSwitchOutputPlugin.IsDeviceAvailable(const ADevice: IAIMPString): Boolean;
var
  I: Integer;
  LCompareResult: Integer;
  LDevices: IAIMPObjectList;
  LItem: IAIMPString;
  LProps: IAIMPPropertyList;
begin
  Result := False;
  if GetPlayerProps(CoreIntf, LProps) then
  begin
    if LProps.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPObjectList, LDevices) = S_OK then
    begin
      for I := 0 to LDevices.GetCount - 1 do
        if Succeeded(LDevices.GetObject(I, IAIMPString, LItem)) and
          (ADevice.Compare(LItem, LCompareResult, True) = S_OK) and
          (LCompareResult = 0)
        then
          Exit(True);
    end;
  end;
end;

function TSwitchOutputPlugin.IsRequiredApiAvailable(ACore: IAIMPCore): Boolean;
var
  LList: IAIMPPropertyList;
  LTemp: IAIMPString;
begin
  Result := GetPlayerProps(ACore, LList) and
    Succeeded(LList.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPString, LTemp));
end;

procedure TSwitchOutputPlugin.OnExecute(Data: IInterface);
var
  LDevice: IAIMPString;
  LPlayer: IAIMPPropertyList;
  LResult: Integer;
begin
  // Show the Settings Dialog if devices are not specified
  if (FDeviceName1 = nil) or (FDeviceName1.GetLength = 0) or
     (FDeviceName2 = nil) or (FDeviceName2.GetLength = 0) then
  begin
    Show(MainWindowGetHandle);
    Exit;
  end;

  // Toggle the outputs
  if GetPlayerProps(CoreIntf, LPlayer) then
  begin
    if LPlayer.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPString, LDevice) = S_OK then
    begin
      if (LDevice.Compare(FDeviceName1, LResult, True) = S_OK) and (LResult = 0) then
        LDevice := FDeviceName2
      else
        LDevice := FDeviceName1;

      if not IsDeviceAvailable(LDevice) then
        PostNotification('Common\aimp.switch.err.unavailable', LDevice)
      else
        if LPlayer.SetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, LDevice) = S_OK then
          PostNotification('OptionsSoundOutFrame\L2', LDevice)
        else
          PostNotification('Common\aimp.switch.err.failed', LDevice);
    end;
  end;
end;

procedure TSwitchOutputPlugin.PostNotification(const AText: string);
var
  LServiceMsg: IAIMPServiceMessageDispatcher;
begin
  if CoreIntf.QueryInterface(IAIMPServiceMessageDispatcher, LServiceMsg) = S_OK then
    LServiceMsg.Send(AIMP_MSG_CMD_SHOW_NOTIFICATION, 0, PChar(AText));
end;

procedure TSwitchOutputPlugin.PostNotification(const ATextId: string; const ADevice: IAIMPString);
var
  LText: string;
begin
  LText := LangLoadString(ATextId);
  if LText = '' then
    LText := ATextId;
  if Pos('%s', LText) > 0 then
    LText := Format(LText, [IAIMPStringToString(ADevice)])
  else
    LText := LText + ' ' + IAIMPStringToString(ADevice);

  PostNotification(LText);
end;

procedure TSwitchOutputPlugin.Show(ParentWindow: HWND);
const
  FormHeight = 200;
  FormWidth = 400;
var
  LForm: IAIMPUIForm;
  LService: IAIMPServiceUI;
  LServiceMUI: IAIMPServiceMUI;

  function Localize(const ID: string): IAIMPString;
  begin
    Result := LangLoadStringEx('Common\aimp.switchoutput.dlg.' + ID);
  end;

  procedure AddLabel(const ACaption: IAIMPString; AHandler: IUnknown = nil);
  var
    LLabel: IAIMPUILabel;
  begin
    if Succeeded(LService.CreateControl(LForm, LForm, nil, AHandler, IAIMPUILabel, LLabel)) then
    begin
      LLabel.SetValueAsInt32(AIMPUI_LABEL_PROPID_AUTOSIZE, 1);
      LLabel.SetValueAsObject(AIMPUI_LABEL_PROPID_TEXT, ACaption);
      LLabel.SetPlacement(TAIMPUIControlPlacement.Create(ualTop, 0, TRect.Create(3, 3, 3, 0)));
      if AHandler <> nil then
        LLabel.SetValueAsObject(AIMPUI_LABEL_PROPID_URL, MakeString(' '));
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

var
  LButton: IAIMPUIButton;
  LConfig: IAIMPServiceConfig;
  LDevice1: IAIMPUIComboBox;
  LDevice2: IAIMPUIComboBox;
  LDevices: IAIMPObjectList;
  LFormPos: TRect;
  LProps: IAIMPPropertyList;
begin
  if Succeeded(CoreIntf.QueryInterface(IAIMPServiceUI, LService)) and
     Succeeded(CoreIntf.QueryInterface(IAIMPServiceMUI, LServiceMUI)) then
  begin
    LDevices := nil;
    if GetPlayerProps(CoreIntf, LProps) then
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
      AddLabel(Localize('hotkeyHint'), TSwitchOutputOpenHotkeysAction.CreateIfAvailable(CoreIntf, LForm));

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
        if Succeeded(CoreIntf.QueryInterface(IAIMPServiceConfig, LConfig)) then
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

{ TSwitchOutputOpenHotkeysAction }

class function TSwitchOutputOpenHotkeysAction.CreateIfAvailable(
  ACore: IAIMPCore; AForm: IAIMPUIForm): IAIMPUIChangeEvents;
var
  LInstance: TSwitchOutputOpenHotkeysAction;
  LService: IAIMPServiceVersionInfo;
begin
  Result := nil;
  if Succeeded(ACore.QueryInterface(IAIMPServiceVersionInfo, LService)) then
  begin
    if LService.GetBuildNumber >= 2400 then // Required API is available since v5.40
    begin
      LInstance := TSwitchOutputOpenHotkeysAction.Create;
      LInstance.FCore := ACore;
      LInstance.FForm := AForm;
      Result := LInstance;
    end;
  end;
end;

procedure TSwitchOutputOpenHotkeysAction.OnChanged(Sender: IInterface);
var
  LRequest: IAIMPConfig;
  LService: IAIMPServiceOptionsDialog;
begin
  if Succeeded(FCore.QueryInterface(IAIMPServiceOptionsDialog, LService)) then
  begin
    FCore.CreateObject(IAIMPConfig, LRequest);
    LRequest.SetValueAsString(MakeString(AIMP_OPT_FRAME_ID), MakeString('20'));
    LRequest.SetValueAsString(MakeString('OptionsFrameHotkeys\Search'),
      LangLoadStringEx('Common\aimp.switchoutput.action.toggle'));
    LService.FrameShow(LRequest, True);
    FForm.Close;
  end;
end;

end.
