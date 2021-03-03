unit uChecker;

interface

uses
  Windows, Classes;

type
  PArrayByte = ^TArrayByte;
  TArrayByte = array[0..0] of Byte;

  TObjectType = (
    otNone,
    otDriver,
    otFile,
    otModule
  );

  // Вероятности должны располагаться от самой маленькой к самой большой
  TAccuracy = (
    accEmpty,
    accLow,
    accMid,
    accHigh
  );

  TReadModuleCallback = reference to function(buff: Pointer; size: DWORD; var needSize: DWORD): DWORD;

  TChecker = class
  private
    class var FCheckerList: TList;
    class var FReadModuleCallback: TReadModuleCallback;

    class procedure SetReadModuleCallback(callback: TReadModuleCallback); static;

  protected
    function GetGuardName(): string; virtual;
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; overload; virtual;

    property GuardName: string read GetGuardName;

  public
    class constructor Create();
    class destructor Destroy();
    class function Check(objectName, sign: string; objType: TObjectType; var guardName: string): TAccuracy; overload;

    class property ReadModuleCallback: TReadModuleCallback read FReadModuleCallback write SetReadModuleCallback;
  end;

  TCheckerActive = class(TChecker)
  protected
    function GetGuardName(): string; override;

  public
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; override;
  end;

  TCheckerSmart3 = class(TChecker)
  protected
    function GetGuardName(): string; override;

  public
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; override;
  end;

  TCheckerSmart2 = class(TChecker)
  protected
    function GetGuardName(): string; override;

  public
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; override;
  end;

  TCheckerFrost = class(TChecker)
  protected
    function GetGuardName(): string; override;

  public
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; override;
  end;

  TCheckerSGuard = class(TChecker)
  protected
    function GetGuardName(): string; override;

  public
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; override;
  end;

  TCheckerStrix = class(TChecker)
  protected
    function GetGuardName(): string; override;

  public
    function Check(objectName, sign: string; objType: TObjectType): TAccuracy; override;
  end;

implementation

uses
  SysUtils;

function Find(template: Pointer; templateSize: Integer; buff: Pointer; buffSize: Integer; offset: Integer = 0): Integer;
var
  i, j: Integer;
  lpT: PArrayByte absolute template;
  lpB: PArrayByte absolute buff;
  found: Boolean;
begin
  // INFO: Если у кого-то есть желание, то может оптимизировать функцию (:
  for i := offset to buffSize - templateSize - 1 do
  begin
    found := True;
    for j := 0 to templateSize - 1 do
    begin
      if (lpT[j] <> lpB[i + j]) then
      begin
        found := False;
        Break;
      end;
    end;

    if (found) then
    begin
      Exit(i);
    end;
  end;

  Result := -1;
end;

//----------------------------------------------------------------------------//
//--------------------------------- TChecker ---------------------------------//
//----------------------------------------------------------------------------//

function TChecker.GetGuardName(): string;
begin
  Result := 'Кто-то накосячил';
end;

function TChecker.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
begin
  Result := accEmpty;
end;

class constructor TChecker.Create();
begin
  ReadModuleCallback := nil;

  FCheckerList := TList.Create();
  FCheckerList.Add(TCheckerActive.Create());
  FCheckerList.Add(TCheckerSmart3.Create());
  FCheckerList.Add(TCheckerSmart2.Create());
  FCheckerList.Add(TCheckerFrost.Create());
  FCheckerList.Add(TCheckerSGuard.Create());
  FCheckerList.Add(TCheckerStrix.Create());
end;

class destructor TChecker.Destroy();
var
  i: Integer;
begin
  for i := 0 to FCheckerList.Count - 1 do
  begin
    TChecker(FCheckerList[i]).Free();
  end;
  FreeAndNil(FCheckerList);
end;

class function TChecker.Check(objectName, sign: string; objType: TObjectType; var guardName: string): TAccuracy;
var
  i: Integer;
  checker: TChecker;
  acc: TAccuracy;
begin
  Result := accEmpty;
  guardName := '';
  objectName := LowerCase(objectName);
  sign := LowerCase(sign);
  // Пробежимся по всем чекерам
  for i := 0 to FCheckerList.Count - 1 do
  begin
    checker := TChecker(FCheckerList[i]);
    acc := checker.Check(objectName, sign, objType);
    // В теории несколько чекеров могут дать положительный результат,
    // поэтому выберем с максимальной вероятностью.
    if (acc > Result) then
    begin
      guardName := checker.GuardName;
      Result := acc;
      if (Result = High(TAccuracy)) then
        Break;
    end;
  end;
end;

class procedure TChecker.SetReadModuleCallback(callback: TReadModuleCallback);
begin
  if (Assigned(callback)) then
    FReadModuleCallback := callback
  else
    FReadModuleCallback := (
      function(lpBuff: Pointer; buffSize: DWORD; var needSize: DWORD): DWORD
      begin
        needSize := 0;
        Result := 0;
      end
    );
end;

//----------------------------------------------------------------------------//
//------------------------------ TCheckerActive ------------------------------//
//----------------------------------------------------------------------------//

function TCheckerActive.GetGuardName(): string;
begin
  Result := 'Active Anticheat';
end;

function TCheckerActive.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
begin
  Result := accEmpty;
  case (objType) of
    otDriver:
      if (0 < Pos('active', objectName)) then
        Result := accMid;

    otFile:
      if (0 < Pos('private', sign)) then
        Result := accMid;
  end;
end;

//----------------------------------------------------------------------------//
//------------------------------ TCheckerSmart3 ------------------------------//
//----------------------------------------------------------------------------//

function TCheckerSmart3.GetGuardName(): string;
begin
  Result := 'SmartGuard 3';
end;

function TCheckerSmart3.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
  function IsCorrectSign(sign: string): Boolean;
  begin
    Result := (0 < Pos('eikonect', sign));
  end;
begin
  Result := accEmpty;
  case (objType) of
    otDriver:
    begin
      if (IsCorrectSign(sign)) then
        Result := accHigh
      else if (0 < Pos('smart', objectName))or(0 < Pos('smrt', objectName)) then
        Result := accMid;
    end;

    otFile:
      if (IsCorrectSign(sign)) then
      begin
        if ('l2.exe' = objectName)or('dsetup.dll' = objectName) then
          Result := accMid;
      end;
  end;
end;

//----------------------------------------------------------------------------//
//------------------------------ TCheckerSmart2 ------------------------------//
//----------------------------------------------------------------------------//

function TCheckerSmart2.GetGuardName(): string;
begin
  Result := 'SmartGuard 2';
end;

function TCheckerSmart2.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
const
  TMPL_FILEINFO: PChar = 'SmartGuard Software';
var
  size, cb: DWORD;
  buff: Pointer;
begin
  Result := accEmpty;
  case (objType) of
    otFile,
    otModule:
      if ('dsetup.dll' = objectName) then
      begin
        ReadModuleCallback(nil, 0, size);
        if (0 = size) then
          Exit;

        GetMem(buff, size);
        try
          size := ReadModuleCallback(buff, size, cb);
          if (size > 0)and(0 < Find(TMPL_FILEINFO, StrLen(TMPL_FILEINFO), buff, size)) then
          begin
            // Последний раз встречал вторую версию Смарта в начале 2019 года,
            // поэтому вероятность определения защиты поставим "низкая".
            Result := accLow;
          end;
        finally
          FreeMem(buff);
        end;
      end;
  end;
end;

//----------------------------------------------------------------------------//
//------------------------------ TCheckerFrost -------------------------------//
//----------------------------------------------------------------------------//

function TCheckerFrost.GetGuardName(): string;
begin
  Result := 'Frost';
end;

function TCheckerFrost.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
begin
  Result := accEmpty;
  case (objType) of
    otDriver:
    begin
      if ((0 < Pos('innova', sign))) then
        Result := accHigh
      else if (0 < Pos('frost', objectName)) then
        Result := accMid;
    end;
  end;
end;

//----------------------------------------------------------------------------//
//------------------------------ TCheckerSGuard ------------------------------//
//----------------------------------------------------------------------------//

function TCheckerSGuard.GetGuardName(): string;
begin
  Result := 'L2s-Guard';
end;

function TCheckerSGuard.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
const
  TMPL_FILEINFO: PChar = 'SmartGua Dynamic Link Library';
var
  size, cb: DWORD;
  buff: Pointer;

  function IsCorrectDll(dllName: string): Boolean;
  begin
    Result := ('guard.des' = dllName)or('dsetup.dll' = objectName);
  end;
  function IsCorrectSign(sign: string): Boolean;
  begin
    Result := (0 < Pos('gameonline', sign))or(0 < Pos('prestrom', sign));
  end;
begin
  Result := accEmpty;
  case (objType) of
    otFile,
    otModule:
    begin
      if (IsCorrectDll(objectName)) then
      begin
        if (IsCorrectSign(sign)) then
          Result := accMid
        else
        begin
          ReadModuleCallback(nil, 0, size);
          if (0 = size) then
            Exit;

          GetMem(buff, size);
          try
            size := ReadModuleCallback(buff, size, cb);
            if (size > 0)and(0 < Find(TMPL_FILEINFO, StrLen(TMPL_FILEINFO), buff, size)) then
            begin
              Result := accMid;
            end;
          finally
            FreeMem(buff);
          end;
        end;
      end;
    end;
  end;
end;

//----------------------------------------------------------------------------//
//------------------------------ TCheckerStrix -------------------------------//
//----------------------------------------------------------------------------//

function TCheckerStrix.GetGuardName(): string;
begin
  Result := 'Strix-Platform';
end;

function TCheckerStrix.Check(objectName, sign: string; objType: TObjectType): TAccuracy;
const
  TMPL_DLSETUP: PChar = 'ASIML: init';
var
  size, cb: DWORD;
  buff: Pointer;
begin
  Result := accEmpty;
  case (objType) of
    otModule:
    begin
      if ('dsetup.dll' = objectName) then
      begin
        ReadModuleCallback(nil, 0, size);
        if (0 = size) then
          Exit;

        GetMem(buff, size);
        try
          size := ReadModuleCallback(buff, size, cb);
          if (size > 0)and(0 < Find(TMPL_DLSETUP, StrLen(TMPL_DLSETUP) * Sizeof(TMPL_DLSETUP[0]), buff, size)) then
          begin
            Result := accMid;
          end;
        finally
          FreeMem(buff);
        end;
      end;
    end;
  end;
end;

end.
