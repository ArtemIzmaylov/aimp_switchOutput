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

library aimp_switchOutput;

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) FIELDS([]) PROPERTIES([])}

uses
  Windows,
  // API
  apiActions,
  apiCore,
  apiGUI,
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
    ActionID = 'aimp.switchoutput.action.id';
  strict private
    FCore: IAIMPCore;
    FDeviceName1: IAIMPString;
    FDeviceName2: IAIMPString;

    function GetPlayerProps(ACore: IAIMPCore; out AProps: IAIMPPropertyList): Boolean;
    function IsRequiredApiAvailable(ACore: IAIMPCore): Boolean;
    function MakeString(const S: UnicodeString): IAIMPString;
  protected
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

  { TSwitchOutputPlugin }

  procedure TSwitchOutputPlugin.Finalize;
  begin
    FCore := nil;
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
        Result := 'SwitchOutput v0.1b';
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

  function TSwitchOutputPlugin.Initialize(Core: IAIMPCore): HRESULT;
  var
    LAction: IAIMPAction;
    LConfig: IAIMPServiceConfig;
  begin
    Result := E_FAIL;
    if IsRequiredApiAvailable(Core) then
    begin
      FCore := Core;
      FCore.CreateObject(IID_IAIMPAction, LAction);
      LAction.SetValueAsObject(AIMP_ACTION_PROPID_ID, MakeString(ActionID));
      LAction.SetValueAsObject(AIMP_ACTION_PROPID_NAME, MakeString('Switch to another output device'));
      LAction.SetValueAsObject(AIMP_ACTION_PROPID_GROUPNAME, MakeString('Output device'));
      LAction.SetValueAsObject(AIMP_ACTION_PROPID_EVENT, Self);
      FCore.RegisterExtension(IAIMPServiceActionManager, LAction);

      if Succeeded(FCore.QueryInterface(IAIMPServiceConfig, LConfig)) then
      begin
        LConfig.GetValueAsString(MakeString('SwitchOutput\Device1'), FDeviceName1);
        LConfig.GetValueAsString(MakeString('SwitchOutput\Device2'), FDeviceName2);
      end;
      Result := S_OK;
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
    LProps: IAIMPPropertyList;
  begin
    if GetPlayerProps(FCore, LProps) then
    begin
      if Succeeded(LProps.GetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, IAIMPString, LDevice)) then
      begin
        if Succeeded(LDevice.Compare(FDeviceName1, LCompareResult, True)) and (LCompareResult = 0) then
          LProps.SetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, FDeviceName2)
        else
          LProps.SetValueAsObject(AIMP_PLAYER_PROPID_OUTPUT, FDeviceName1);
      end;
    end;
  end;

  procedure TSwitchOutputPlugin.Show(ParentWindow: HWND);
  const
    FormHeight = 200;
    FormWidth = 340;
  var
    LForm: IAIMPUIForm;
    LService: IAIMPServiceUI;

    procedure AddLabel(const ACaption: string);
    var
      LLabel: IAIMPUILabel;
    begin
      if Succeeded(LService.CreateControl(LForm, LForm, nil, nil, IAIMPUILabel, LLabel)) then
      begin
        LLabel.SetValueAsInt32(AIMPUI_LABEL_PROPID_AUTOSIZE, 1);
        LLabel.SetValueAsObject(AIMPUI_LABEL_PROPID_TEXT, MakeString(ACaption));
        LLabel.SetPlacement(TAIMPUIControlPlacement.Create(ualTop, 0));
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
    if Succeeded(FCore.QueryInterface(IAIMPServiceUI, LService)) then
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
        LForm.SetValueAsObject(AIMPUI_FORM_PROPID_CAPTION, MakeString('Settings'));
        LForm.SetValueAsInt32(AIMPUI_FORM_PROPID_BORDERSTYLE, AIMPUI_FLAGS_BORDERSTYLE_DIALOG);
        LForm.SetValueAsInt32(AIMPUI_FORM_PROPID_PADDING, 8);

        AddLabel('Device 1:');
        LDevice1 := AddComboBox(LDevices, FDeviceName1);
        AddLabel('Device 2:');
        LDevice2 := AddComboBox(LDevices, FDeviceName2);
        AddLabel('[!] Refer to app Settings\Player\Hotkeys to setup a hotkey');

        if Succeeded(LService.CreateControl(LForm, LForm, nil, nil, IAIMPUIButton, LButton)) then
        begin
          LButton.SetValueAsInt32(AIMPUI_BUTTON_PROPID_MODALRESULT, idOK);
          LButton.SetValueAsObject(AIMPUI_BUTTON_PROPID_CAPTION, MakeString('Œ '));
          LButton.SetPlacement(TAIMPUIControlPlacement.Create(ualBottom, 25, TRect.Create(200, 0, 0, 0)));
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

  { AIMPPluginGetHeader }

  function AIMPPluginGetHeader(out Header: IAIMPPlugin): HRESULT; stdcall;
  begin
    Header := TSwitchOutputPlugin.Create;
    Result := S_OK;
  end;

exports
  AIMPPluginGetHeader;
begin
end.
