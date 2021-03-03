program L2GChecker;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {fmMain},
  uCert in 'uCert.pas',
  RegExpr in 'RegExpr.pas',
  uChecker in 'uChecker.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
