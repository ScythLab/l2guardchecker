unit uMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Forms, Controls,
  Dialogs, Grids, ComCtrls, Menus, StdCtrls, Generics.Collections, RegExpr;

const
  // "Стандартные" расширения исполняемых файлов Lineage.
  // Использовать "bak" крайне спорно, но такие сервера иногда попадаются.
  REGEXP_EXT_LIST = '\.(exe|bin|bak)$';
  // "Стандартные" имена исполняемых файлов Lineage.
  REGEXP_PROC_LIST = '(l2|asteriosgame|endlesswar|bsfg)\.[^.]+$';
  // Список "стандартных" библиотек, которые, как правило, не относятся к защитам.
  REGEXP_DLL_LIST = '^(core|engine|window|nwindow|awesomium|fire|.*openal.*|alaudio|wrap_oal|d3ddrv|windrv|npks?crypt|npkpdb|game_presence-?\d*|vorbis|vorbisfile|ogg|ifc23|libcef|steam_api|beecrypt|bass|fmode?x?|dbghelp|libgmp-?\d*|libz-?\d*|msvcr\d*|vcomp\d*|bdcam)\.dll$';
  // Список цифровых подписей, встречающихся в Lineage и не относящихся к защитам.
  REGEXP_SIGN_LIST = '(NCSOFT Corp|Khrona LLC|Awesomium Technologies LLC|Valve|Microsoft Corporation)';

type
  TfmMain = class(TForm)
    lvList: TListView;
    pmList: TPopupMenu;
    miProperty: TMenuItem;
    mmMain: TMainMenu;
    miDriver: TMenuItem;
    miDriverList: TMenuItem;
    miSnapshot: TMenuItem;
    miDiff: TMenuItem;
    miLineage: TMenuItem;
    miCheckSystem: TMenuItem;
    dlgPath: TFileOpenDialog;
    mmLog: TMemo;
    miProcList: TMenuItem;
    miHelp: TMenuItem;
    miYManual: TMenuItem;
    miManual: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure miPropertyClick(Sender: TObject);
    procedure lvListDrawItem(Sender: TCustomListView; Item: TListItem;
      Rect: TRect; State: TOwnerDrawState);
    procedure FormDestroy(Sender: TObject);
    procedure miDriverListClick(Sender: TObject);
    procedure miSnapshotClick(Sender: TObject);
    procedure miDiffClick(Sender: TObject);
    procedure miCheckSystemClick(Sender: TObject);
    procedure miLineageClick(Sender: TObject);
    procedure miYManualClick(Sender: TObject);
    procedure miManualClick(Sender: TObject);

  private
    FDriverList: TDictionary<UIntPtr, string>;
    FTempDir: string;
    FTempFileName: string;
    FWinDir: string;
    FStandartLibList: TRegExpr;
    FStandartSignList: TRegExpr;

    procedure AddLog(str: string); overload;
    procedure AddLog(const fmt: string; const args: array of const); overload;
    function GetDriverList(list: TDictionary<UIntPtr, string>): Boolean;
    procedure AddObjectToList(presentation: string); overload;
    procedure AddObjectToList(presentation, name, path, sign, guard: string; size: Integer = 0; state: Integer = 0; index: Integer = -1); overload;
    procedure AddDriverToList(driverName: string; state: Integer = 0);
    function IsStandartLib(fileName: string): Boolean;
    function IsStandartSign(sign: string): Boolean;
    procedure ClearList();

    procedure ProcClick(Sender: TObject);

  public
    { Public declarations }
  end;

var
  fmMain: TfmMain;

implementation

uses
  StrUtils, Math, UITypes, PsApi, ShellApi, TlHelp32,
  uCert, uChecker;

{$R *.dfm}

const
  STATE_NONE      = 0;
  STATE_NEW       = 1;
  STATE_REMOVED   = 2;
  STATE_WARNING   = 3;

  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  PArPointer = ^TArPointer;
  TArPointer = array[0..0] of Pointer;
  TWow64DisableWow64FsRedirection = function(var wow64FsEnableRedirection: LongBool): LongBool; stdcall;

  TProcInfo = class
    Id: DWORD;
    Name: string;
    ExeName: string;
  end;

  TObjectInfo = class
    Presentation: string;
    Name: string;
    Path: string;
    Sign: string;
    Guard: string;
    State: Integer;
  end;

var
  Wow64DisableWow64FsRedirection: TWow64DisableWow64FsRedirection;
  IsWinXp: Boolean;
  AdminRights: Boolean;

procedure ShowProperties(fileName: string);
var
  info: TShellExecuteInfo;
begin
  FillChar(info, SizeOf(info), 0);
  info.cbSize := SizeOf(info);
  info.lpFile := @fileName[1];
  info.nShow := SW_SHOW;
  info.fMask := SEE_MASK_INVOKEIDLIST;
  info.lpVerb := 'properties';
  ShellExecuteEx(@info);
end;

function GetRawDelta(lpNtHeaders: PImageNtHeaders; addr: DWORD): Integer;
var
  lpSection: PImageSectionHeader;
  i: Integer;
begin
  lpSection := IMAGE_FIRST_SECTION(lpNtHeaders^);
  for i := 0 to lpNtHeaders.FileHeader.NumberOfSections - 1 do
  begin
    if (addr >= lpSection.VirtualAddress) and (addr < lpSection.VirtualAddress + lpSection.SizeOfRawData) then
      Exit(lpSection.VirtualAddress - lpSection.PointerToRawData);

    Inc(lpSection);
  end;

  Result := -1;
end;

function SizeToStr(size: DWORD): string;
const
  SUFIX_COUNT = 4;
  SUFIX_LIST: array[0..SUFIX_COUNT - 1] of string = ('', 'k', 'M', 'G');
var
  i: Integer;
  modValue, v: DWORD;
begin
  modValue := 1;
  for i := 0 to SUFIX_COUNT - 1 do
  begin
    v := size div modValue;
    if (v < 1000)or(SUFIX_COUNT - 1 = i) then
      Exit(Format('%d%s', [v, SUFIX_LIST[i]]));

    modValue := modValue * 1000;
  end;

  Result := '';
end;

function AccuracyToStr(acc: TAccuracy): string;
begin
  case (acc) of
    accLow:  Result := 'НИЗ';
    accMid:  Result := 'СРЕД';
    accHigh: Result := 'ВЫС';
    else     Result := '';
  end;
end;

function GetProcList(pattern: string): TList;
var
  hSnapshotProc: THandle;
  pe32: TProcessEntry32;
  procFileName: string;
  info: TProcInfo;
  exp: TRegExpr;
  hProc: THandle;
  wow64Proc: LongBool;
  exeName: array[0..MAX_PATH - 1] of Char;
  access: DWORD;
begin
  Result := TList.Create();

  FillChar(pe32, SizeOf(pe32), 0);
  pe32.dwSize := SizeOf(pe32);
  hSnapshotProc := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (INVALID_HANDLE_VALUE = hSnapshotProc) then
    Exit;

  exp := nil;
  try
    if (not Process32First(hSnapshotProc, pe32)) then
      Exit;

    exp := TRegExpr.Create();
    exp.ModifierI := True;
    exp.Expression := pattern;

    repeat
      if (pe32.th32ProcessID in [0, 4])or(GetCurrentProcessId() = pe32.th32ProcessID) then
        Continue;

      // Выделим только имя процесса
      procFileName := ExtractFileName(LowerCase(pe32.szExeFile));

      if (not exp.Exec(procFileName)) then
        Continue;

      access := IfThen(IsWinXp, PROCESS_QUERY_INFORMATION, PROCESS_QUERY_LIMITED_INFORMATION);
      hProc := OpenProcess(access, False, pe32.th32ProcessID);
      if (0 = hProc) then
        Continue;

      if (not IsWow64Process(hProc, wow64Proc)) then
        wow64Proc := False;
      if (0 = GetModuleFileNameEx(hProc, 0, exeName, MAX_PATH)) then
        exeName[0] := #0;
      CloseHandle(hProc);
      if (not wow64Proc) then
        Continue;

      info := TProcInfo.Create();
      Result.Add(info);
      info.Id := pe32.th32ProcessID;
      info.Name := procFileName;
      info.ExeName := exeName;
    until ( not Process32Next(hSnapshotProc, pe32) );
  finally
    CloseHandle(hSnapshotProc);
    if (nil <> exp) then
      exp.Free();
  end;
end;

function FindExeFiles(path: string): TStrings;
var
  sRec: TSearchRec;
  rexp: TRegExpr;
begin
  Result := TStringList.Create();
  if (0 <> FindFirst(path + '*.*', faAnyFile, sRec)) then
    Exit;

  rexp := nil;
  try
    rexp := TRegExpr.Create();
    rexp.ModifierI := True;
    rexp.Expression := REGEXP_EXT_LIST;
    repeat
      if (rexp.Exec(sRec.Name)) then
        Result.Add(LowerCase(sRec.Name));
    until (0 <> FindNext(sRec));
  finally
    FindClose(sRec);
    if (nil <> rexp) then
      rexp.Free();
  end;
end;

// Определяет есть ли у программы права админа.
// Код взят с просторов интернета.
function IsAdmin(): Boolean;
const
  SECURITY_NT_AUTHORITY: TSIDIdentifierAuthority = (Value: (0, 0, 0, 0, 0, 5));
  SECURITY_BUILTIN_DOMAIN_RID = $00000020;
  DOMAIN_ALIAS_RID_ADMINS = $00000220;
var
  hAccessToken: THandle;
  ptgGroups: PTokenGroups;
  dwInfoBufferSize: DWORD;
  psidAdministrators: PSID;
  Idx: Integer;
  bSuccess: BOOL;
begin
  Result   := False;
  bSuccess := OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, True, hAccessToken);
  if (not bSuccess)and(ERROR_NO_TOKEN = GetLastError()) then
    bSuccess := OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, hAccessToken);
  if bSuccess then
  begin
    GetTokenInformation(hAccessToken, TokenGroups, nil, 0, dwInfoBufferSize);
    ptgGroups := GetMemory(dwInfoBufferSize);
    bSuccess := GetTokenInformation(hAccessToken, TokenGroups, ptgGroups, dwInfoBufferSize, dwInfoBufferSize);
    CloseHandle(hAccessToken);
    if bSuccess then
    begin
      AllocateAndInitializeSid(SECURITY_NT_AUTHORITY, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, psidAdministrators);
      {$R-}
      for Idx := 0 to ptgGroups.GroupCount - 1 do
      begin
        if (SE_GROUP_ENABLED = (ptgGroups.Groups[Idx].Attributes and SE_GROUP_ENABLED)) and EqualSid(psidAdministrators, ptgGroups.Groups[Idx].Sid) then
        begin
          Result := True;
          Break;
        end;
      end;
      {$R+}
      FreeSid(psidAdministrators);
    end;
    FreeMem(ptgGroups);
  end;
end;

//----------------------------------------------------------------------------//
//--------------------------------- TfmMain ----------------------------------//
//----------------------------------------------------------------------------//

procedure TfmMain.AddLog(str: string);
var
  sDt: string;
begin
  DateTimeToString(sDt, 'HH:mm:ss', Now());
  mmLog.Lines.Add(Format('[%s] %s', [sDt, str]));
end;

procedure TfmMain.AddLog(const fmt: string; const args: array of const);
begin
  AddLog(Format(fmt, args));
end;

function TfmMain.GetDriverList(list: TDictionary<UIntPtr, string>): Boolean;
var
  i, cDrivers: Integer;
  cbNeeded, size: DWORD;
  drivers: PArPointer;
  driverName: array[0..MAX_PATH - 1] of Char;
  fileName: string;
  fullFileName: array[0..MAX_PATH - 1] of Char;
  driverAddr: UIntPtr;
begin
  list.Clear();
  Result := False;
  if (not EnumDeviceDrivers(nil, 0, cbNeeded)) then
    Exit;

  size := cbNeeded + 100;
  GetMem(drivers, size);
  try
    if (not EnumDeviceDrivers(PPointer(drivers), size, cbNeeded))or(cbNeeded = 0)or(cbNeeded > size) then
      Exit;

    cDrivers := cbNeeded div SizeOf(drivers[0]);
    for i := 0 to cDrivers - 1 do
    begin
      {$R-}
      driverAddr := UIntPtr(drivers[i]);
      {$R+}
      //if (0 = GetDeviceDriverBaseName(Pointer(driverAddr), driverName, MAX_PATH)) then
      //  Continue;
      if (0 = GetDeviceDriverFileName(Pointer(driverAddr), driverName, MAX_PATH)) then
        Continue;

      // TRICKY: Приведем путь в нормальный вид.
      // В https://www.codeproject.com/Articles/18704/Process-viewer
      // используется спец функция SearchPath, но не будем так заморачиваться.
      fileName := driverName;
      fileName := StringReplace(fileName, '\systemroot\', '%systemroot%\', [rfIgnoreCase]);
      fileName := StringReplace(fileName, '\??\', '', []);
      ExpandEnvironmentStrings(@fileName[1], fullFileName, MAX_PATH);
      fileName := fullFileName;

      if (not list.TryAdd(driverAddr, fileName)) then
        AddLog('Дубль: 0x%08x %s', [DWORD(driverAddr), string(driverName)]);
    end;
  finally
    FreeMem(drivers);
  end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
var
  bl: LongBool;
  lps: array[0..MAX_PATH - 1] of Char;
  hLib: THandle;
begin
  //ReportMemoryLeaksOnShutdown := True;

  mmLog.Clear();
  FDriverList := TDictionary<UIntPtr, string>.Create();
  // Список "стандартных" библиотек, которые, как правило, не относятся к защитам.
  FStandartLibList := TRegExpr.Create();
  FStandartLibList.ModifierI := True;
  FStandartLibList.Expression := REGEXP_DLL_LIST;
  // Список цифровых подписей, встречающихся в Lineage и не относящихся к защитам.
  FStandartSignList := TRegExpr.Create();
  FStandartSignList.ModifierI := True;
  FStandartSignList.Expression := REGEXP_SIGN_LIST;

  hLib := GetModuleHandle('kernel32.dll');
  if (0 <> hLib) then
  begin
    Wow64DisableWow64FsRedirection := getProcAddress(hLib, 'Wow64DisableWow64FsRedirection');
    if (Assigned(Wow64DisableWow64FsRedirection)) then
      Wow64DisableWow64FsRedirection(bl);
  end;
  if (0 < GetTempPath(MAX_PATH, lps)) then
  begin
    FTempDir := IncludeTrailingPathDelimiter(Trim(lps));
  end;
  if (FTempDir <> '') then
    FTempFileName := FTempDir + 'checker.temp'
  else
    FTempFileName := '';

  if (0 < GetWindowsDirectory(lps, MAX_PATH)) then
    FWinDir := LowerCase(lps)
  else
    FWinDir := 'c:\windows\';
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  ClearList();
  FreeAndNil(FDriverList);
  FreeAndNil(FStandartLibList);
  FreeAndNil(FStandartSignList);
end;

procedure TfmMain.AddObjectToList(presentation: string);
begin
  AddObjectToList(presentation, '', '', '', '');
end;

procedure TfmMain.AddObjectToList(presentation, name, path, sign, guard: string; size: Integer = 0; state: Integer = STATE_NONE; index: Integer = -1);
var
  item: TListItem;
  obj: TObjectInfo;
begin
  if (presentation = '') then
  begin
    // Перед именем файла поставим его размер - полезно при определение модулей защиты.
    if (size > 0) then
      presentation := Format('%s |  %s', [SizeToStr(size), name])
    else
      presentation := name;
  end;

  // Если определили защиту, то поставим объект в начало списка.
  if (-1 = index)and('' <> guard) then
    index := 0;
  // Если по какой-либо причине объект ставится в начало списка,
  // то выделим его цветом.
  if (STATE_NONE = state)and(-1 <> index) then
    state := STATE_WARNING;

  obj := TObjectInfo.Create();
  obj.Presentation := presentation;
  obj.Name := name;
  obj.Path := path;
  obj.Sign := sign;
  obj.Guard := guard;
  obj.State := state;

  item := lvList.Items.Insert(index);
  item.Data := obj;
  item.Caption := presentation;
  item.SubItems.Add(sign);
  item.SubItems.Add(guard);
end;

procedure TfmMain.AddDriverToList(driverName: string; state: Integer = 0);
var
  fileName: string;
  needDeleteTemp: Boolean;
  name, path, sign, guardName: string;
  acc: TAccuracy;
begin
  // Большинство драйверов находятся в папке "system32/drivers", получение информации из этой папки не работает,
  // делать проверки лень, поэтому будем перекидывать все файлы во временную папку.
  fileName := driverName;
  needDeleteTemp := False;
  if ('' <> FTempFileName) then
  begin
    if (CopyFile(PChar(driverName), PChar(FTempFileName), False)) then
    begin
      fileName := FTempFileName;
      needDeleteTemp := True;
    end;
  end;
  sign := GetCompaniesSigningCertificate(fileName);
  if (needDeleteTemp) then
    DeleteFile(FTempFileName);

  path := ExtractFilePath(driverName);
  name := ExtractFileName(driverName);

  acc := TChecker.Check(name, sign, otDriver, guardName);
  if (accEmpty <> acc) then
    guardName := Format('%s %s', [AccuracyToStr(acc), guardName]);

  AddObjectToList(driverName, name, path, sign, guardName, 0, state);
end;

function TfmMain.IsStandartLib(fileName: string): Boolean;
begin
  Result := FStandartLibList.Exec(fileName);
end;

function TfmMain.IsStandartSign(sign: string): Boolean;
begin
  Result := FStandartSignList.Exec(sign);
end;

procedure TfmMain.ClearList();
var
  i: Integer;
  info: TObjectInfo;
begin
  // Очистим список, предварительно освободив рабочие данные.
  for i := 0 to lvList.Items.Count - 1 do
  begin
    info := TObjectInfo(lvList.Items[i].Data);
    if (Assigned(info)) then
      info.Free();
  end;
  lvList.Clear();
end;

procedure TfmMain.lvListDrawItem(Sender: TCustomListView; Item: TListItem;
  Rect: TRect; State: TOwnerDrawState);
const
  TEXT_MARGIN = 2;
var
  r: TRect;
  cl: TColor;
  i, maxI: Integer;
  s: string;
  info: TObjectInfo;
begin
  // MoneyGreen, Honeydew - светлозеленый
  // Lightgreen - яркий зеленый
  // Aliceblue - светлоголубой
  // Mistyrose  - светлорозовый
  // Antiquewhite, Moccasin, Navajowhite - желтоватый
  // Coral, Pink - розовый

  info := TObjectInfo(item.Data);
  // Фон
  case DWORD(info.State) of
    STATE_NEW:     cl := TColorRec.MoneyGreen;
    STATE_REMOVED: cl := TColorRec.Mistyrose;
    STATE_WARNING: cl := TColorRec.Antiquewhite;
    else           cl := clWindow;
  end;
  Sender.Canvas.Brush.Color := cl;
  Sender.Canvas.FillRect(Rect);

  // Текст
  r := Rect;
  maxI := Min(TListView(Sender).Columns.Count - 1, Item.SubItems.Count);
  for i := 0 to maxI do
  begin
    if (0 = i) then
      s := Item.Caption
    else
      s := Item.SubItems[i - 1];

    r.Width := Sender.Column[i].Width - TEXT_MARGIN;
    r.Right := Min(r.Right, Rect.Right);
    Sender.Canvas.TextRect(r, r.Left + TEXT_MARGIN, r.Top + TEXT_MARGIN, s);
    r.Left := r.Right + TEXT_MARGIN;
  end;
end;

procedure TfmMain.miPropertyClick(Sender: TObject);
var
  i: Integer;
  info: TObjectInfo;
begin
  i := lvList.ItemIndex;
  if (i < 0)or(i >= lvList.Items.Count) then
    Exit;

  info := TObjectInfo(lvList.Items[i].Data);
  if ('' = info.Name) then
    Exit;

  ShowProperties(info.Path + info.Name);
end;

procedure TfmMain.miDriverListClick(Sender: TObject);
var
  driverName: string;
  list: TDictionary<UIntPtr, string>;
begin
  ClearList();
  TChecker.ReadModuleCallback := nil;
  list := TDictionary<UIntPtr, string>.Create();
  try
    GetDriverList(list);
    for driverName in list.Values do
    begin
      AddDriverToList(driverName);
    end;
  finally
    list.Free();
  end;
end;

procedure TfmMain.ProcClick(Sender: TObject);
var
  hProc: THandle;
  item: TMenuItem absolute Sender;
  cb, size, modSize: DWORD;
  modules, lpMod: PHModule;
  hMod: HModule;
  i: Integer;
  lpModuleName: array[0..MAX_PATH - 1] of Char;
  modName, sign, guardName: string;
  modInfo: TModuleInfo;
  acc: TAccuracy;
  name, path: string;
  insertIndex: Integer;

  procedure ShowAccessDenied();
  var
    s: string;
  begin
    s := '';
    if (not AdminRights) then
      s := ' (запустите детектор от имени администратора)';
    AddObjectToList(Format('[Нет доступа] %s%s', [item.Caption, s]));
  end;
begin
  ClearList();
  hProc := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, item.Tag);
  if (hProc = 0) then
  begin
    ShowAccessDenied();
    Exit;
  end;

  modules := nil;
  TChecker.ReadModuleCallback := (
    function(buff: Pointer; size: DWORD; var needSize: DWORD): DWORD
    var
      cb: NativeUInt;
    begin
      Result := 0;
      if (nil = buff)or(size > modInfo.SizeOfImage) then
      begin
        needSize := modInfo.SizeOfImage;
        Exit;
      end;

      if (ReadProcessMemory(hProc, modInfo.lpBaseOfDll, buff, size, cb)) then
      begin
        Result := cb;
      end;
    end
  );

  try
    if (not EnumProcessModules(hProc, nil, 0, size))or(0 = size) then
    begin
      ShowAccessDenied();
      Exit;
    end;

    Inc(size, SizeOf(THandle) * 10);
    GetMem(modules, size);
    if (not EnumProcessModules(hProc, modules, size, cb))or(cb > size) then
      Exit;

    lpMod := modules;
    for i := 0 to (cb div SizeOf(THandle)) - 1 do
    begin
      hMod := lpMod^;
      Inc(lpMod);
      sign := '';
      if (0 < GetModuleFileNameEx(hProc, hMod, lpModuleName, MAX_PATH)) then
      begin
        modName := lpModuleName;
        if (StartsText(FWinDir, LowerCase(modName))) then
          Continue;

        sign := GetCompaniesSigningCertificate(modName);
      end
      else
        modName := Format('%x', [hMod]);

      path := ExtractFilePath(modName);
      name := ExtractFileName(modName);

      modSize := 0;
      if (GetModuleInformation(hProc, hMod, @modInfo, SizeOf(modInfo))) then
        modSize := modInfo.SizeOfImage;

      acc := TChecker.Check(name, sign, otModule, guardName);
      if (accEmpty <> acc) then
        guardName := Format('%s %s', [AccuracyToStr(acc), guardName]);

      // "Нестандартные" библиотеки вынесем вверх списка.
      insertIndex := -1;
      if (i > 0)and(not IsStandartLib(name)) then
        insertIndex := 0;

      AddObjectToList('', name, path, sign, guardName, modSize, STATE_NONE, insertIndex);
    end;

  finally
    CloseHandle(hProc);
    if (nil <> modules) then
      FreeMem(modules);
  end;
end;

procedure TfmMain.miLineageClick(Sender: TObject);
var
  procList: TList;
  i: Integer;
  item: TMenuItem;
  info: TProcInfo;
begin
  miProcList.Clear();
  // "Стандартные" имена исполняемых файлов Lineage.
  procList := GetProcList(REGEXP_PROC_LIST);
  if (0 = procList.Count) then
  begin
    item := TMenuItem.Create(miProcList);
    item.Caption := 'Нет процессов';
    miProcList.Add(item);
  end;

  for i := 0 to procList.Count - 1 do
  begin
    info := TProcInfo(procList[i]);

    item := TMenuItem.Create(miProcList);
    item.Caption := Format('%s [%d]', [info.Name, info.Id]);
    item.Tag := info.Id;
    item.OnClick := ProcClick;
    miProcList.Add(item);
    info.Free();
  end;
  procList.Free();
end;

procedure TfmMain.miSnapshotClick(Sender: TObject);
begin
  GetDriverList(FDriverList);
end;

procedure TfmMain.miYManualClick(Sender: TObject);
begin
  ShellExecute(0, 'open', 'https://www.youtube.com/watch?v=ZoOS4hfx3DM', nil, nil, SW_SHOW);
end;

procedure TfmMain.miManualClick(Sender: TObject);
begin
  MessageDlg(''
    + 'Детектор написан в январе 2021 года.'#13#10
    + 'На момент написания мог с высокой точностью определять защиты: Active Anticheat, SmartGuard 2/3, Frost, L2s-Guard, Strix-Platform.'#13#10
    + ''#13#10
    + 'В детекторе реализовано 3 функции по определению защиты.'#13#10
    + 'Каждая функция в таблице показывает потенциально интересные файлы.'#13#10
    + 'В столбце Защита, указывается название защиты и точность определения.'#13#10
    + 'Для полной проверки необходимо выполнить все 3 функции и ориентироваться на суммарный результат.'#13#10
    + 'Если хотя бы 1 из функций выдаст ВЫСокую точность, либо две функции дадут СРЕДнюю точность, то можно считать определение защиты успешным. В противном случае обратитесь к своему разуму.'#13#10
    + ''#13#10
    + 'ПОЛУАВТОМАТИЧЕСКИЙ АНАЛИЗ'#13#10
    + 'Перед использованием детектора обязательно перезагрузить компьютер.'#13#10
    + 'Для одного клиента Lineage по очереди выполните все 3 функции.'#13#10
    + 'Если необходимо проверить другой клиент Lineage и на второй функции детектор показал какие-либо файлы, то требуется повторная перезагрузка компьютера.'#13#10
    + ''#13#10
    + '1 функция:'#13#10
    + ' - нажмите меню Lineage -> Сканер system'#13#10
    + ' - выберите папку system с игрой'#13#10
    + ''#13#10
    + '2 функция:'#13#10
    + ' - нажмите меню Драйверы -> Снимок'#13#10
    + ' - запустите клиент Lineage'#13#10
    + ' - нажмите меню Драйверы -> Сравнение'#13#10
    + ''#13#10
    + '3 функция:'#13#10
    + ' - при запущенной игре выберите в меню Lineage -> Процесс -> игру'#13#10
    + ''#13#10
    + 'ScythLab '#169,
    mtInformation, [mbOK], 0);
end;

procedure TfmMain.miCheckSystemClick(Sender: TObject);
var
  path: string;
  fileList: TStrings;
  index, exeCount: Integer;

  function IncF(f_X: Pointer; f_N: UInt64): Pointer;
  begin
    Result := Pointer(UInt64(f_X) + f_N);
  end;
  procedure AddFile(name: string);
  begin
    name := LowerCase(name);
    if (-1 <> fileList.IndexOf(name)) then
      Exit;

    fileList.Add(name);
  end;
  procedure CheckFile(name: string; isExe: Boolean);
  var
    buff: Pointer;
    hFile: THandle;
    fileSize, cb, dirSize: DWORD;
    lpDosHeader: PImageDosHeader;
    lpNtHeaders: PImageNtHeaders;
    lpDirectory: PImageDataDirectory;
    lpImportDesc: PImageImportDescriptor;
    lpDllName: PAnsiChar;
    sDllName: string;
    sign, guardName: string;
    rawDelta: Integer;
    acc: TAccuracy;
  begin
    TChecker.ReadModuleCallback := (
      function(lpBuff: Pointer; buffSize: DWORD; var needSize: DWORD): DWORD
      begin
        Result := 0;
        if (nil = lpBuff)or(buffSize > fileSize) then
        begin
          needSize := fileSize;
          Exit;
        end;

        Move(buff^, lpBuff^, buffSize);
        Result := buffSize;
      end
    );

    hFile := CreateFile(PChar(path + name), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
    if (INVALID_HANDLE_VALUE = hFile) then
      Exit;

    buff := nil;
    try
      fileSize := GetFileSize(hFile, nil);
      if (0 = fileSize) then
        Exit;
      GetMem(buff, fileSize);
      if (not ReadFile(hFile, buff^, fileSize, cb, nil)) then
        Exit;

      // Проверка заголовка образа
      lpDosHeader := PImageDosHeader(buff);
      if (IMAGE_DOS_SIGNATURE <> lpDosHeader.e_magic) then
        Exit;
      lpNtHeaders := PImageNtHeaders(ULONG_PTR(lpDosHeader) + DWORD(lpDosHeader._lfanew));
      if (IMAGE_NT_SIGNATURE <> lpNtHeaders.Signature) then
        Exit;

      // Работаем только с x32 образами
      if (IMAGE_FILE_MACHINE_I386 <> lpNtHeaders.FileHeader.Machine) then
        Exit;

      // Проверим подпись файла
      sign := GetCompaniesSigningCertificate(path + name);

      acc := TChecker.Check(name, sign, otFile, guardName);
      if (accEmpty <> acc) then
        guardName := Format('%s %s', [AccuracyToStr(acc), guardName]);
      if (('' <> sign)and(not IsStandartSign(sign)))or('' <> guardName)or((not isExe)and(not IsStandartLib(name))) then
        AddObjectToList('', name, path, sign, guardName, fileSize);

      // Проверим таблицу импорта
      lpDirectory := @lpNtHeaders.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
      if (0 = lpDirectory.Size) then
        Exit;

      rawDelta := GetRawDelta(lpNtHeaders, lpDirectory.VirtualAddress); // Смещение виртуального адреса относительно файла
      if (-1 = rawDelta) then
      begin
        AddLog('Плохая таблица импорта в файле %s', [name]);
        Exit;
      end;

      lpImportDesc := IncF(buff, lpDirectory.VirtualAddress - DWORD(rawDelta));
      dirSize := 0;
      // BUG: В некоторых образах таблица подпорчена, как это правильно разрулить непонятно,
      // поэтому на таких таблицах функция может сваливаться.
      while (lpImportDesc.Name > 0)and(dirSize < lpDirectory.Size) do
      begin
        rawDelta := GetRawDelta(lpNtHeaders, lpImportDesc.Name);
        if (-1 = rawDelta) then
        begin
          AddLog('Запорчена таблица импорта в файле %s', [name]);
          Exit;
        end;
        lpDllName := IncF(buff, lpImportDesc.Name - DWORD(rawDelta));
        sDllName := string(AnsiString(lpDllName));

        // Если библиотека расположена в папке с программой, то добавим ее в список проверки.
        // Т.е. игнорируем все виндовые библиотеки.
        if (FileExists(path + sDllName)) then
          AddFile(sDllName);

        Inc(lpImportDesc);
        Inc(dirSize, SizeOf(TImageImportDescriptor));
      end;
    finally
      CloseHandle(hFile);
      if (nil <> buff) then
        FreeMem(buff);
    end;
  end;
begin
  ClearList();
  if (not dlgPath.Execute()) then
    Exit;

  path := IncludeTrailingPathDelimiter(dlgPath.FileName);

  fileList := FindExeFiles(path);
  index := 0;
  exeCount := fileList.Count;
  while (index < fileList.Count) do
  begin
    try
      CheckFile(fileList[index], index < exeCount);
    except
      AddLog('Ошибка проверки файла: %s', [fileList[index]]);
    end;
    Inc(index);
  end;
  fileList.Free();
end;

procedure TfmMain.miDiffClick(Sender: TObject);
var
  list: TDictionary<UIntPtr, string>;
  key: UIntPtr;
begin
  ClearList();
  TChecker.ReadModuleCallback := nil;
  list := TDictionary<UIntPtr, string>.Create();
  try
    GetDriverList(list);

    // Вначале найдем новые записи
    for key in list.Keys do
    begin
      if (FDriverList.ContainsKey(key)) then
        Continue;

      AddDriverToList(list[key], STATE_NEW);
    end;

    // Затем найдем удаленные записи
    for key in FDriverList.Keys do
    begin
      if (list.ContainsKey(key)) then
        Continue;

      AddDriverToList(FDriverList[key], STATE_REMOVED);
    end;
  finally
    list.Free();
  end;
end;

initialization
  IsWinXp := (5 = (GetVersion() and $FF));
  AdminRights := IsAdmin();

end.

