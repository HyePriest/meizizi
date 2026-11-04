#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
#ifndef BundleDir
  #error BundleDir must point to the prepared Windows application folder.
#endif
#ifndef OutputDir
  #define OutputDir "..\releases"
#endif

[Setup]
AppId=com.jknl.meizizi.windows
AppName=美滋滋
AppVersion={#AppVersion}
AppPublisher=HyePriest
AppPublisherURL=https://github.com/HyePriest/meizizi
AppSupportURL=https://github.com/HyePriest/meizizi/issues
DefaultDirName={localappdata}\Programs\meizizi
DefaultGroupName=美滋滋
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
DisableDirPage=no
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes
UninstallDisplayIcon={app}\meizizi.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=meizizi-windows-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=meizizi.exe
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\美滋滋"; Filename: "{app}\meizizi.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\美滋滋"; Filename: "{app}\meizizi.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\meizizi.exe"; Description: "启动美滋滋"; Flags: nowait postinstall skipifsilent

; Account credentials and preferences live in the user's application-data
; directory. Do not add deletion rules for that directory on upgrade/uninstall.
