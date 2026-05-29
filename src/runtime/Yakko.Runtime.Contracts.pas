unit Yakko.Runtime.Contracts;

{ Runtime contracts foundation for YakkoDelphiLLM.

  Architectural intent:
  - define minimal stable interfaces for lifecycle, debugging and metadata;
  - improve testability via explicit component contracts;
  - prepare mocks and unit tests without changing runtime behavior.

  This unit intentionally avoids dependency injection containers, service locators
  and runtime discovery mechanisms. }

interface

uses
  System.Generics.Collections;

type
  IYakkoRuntimeComponent = interface
    ['{307F8CE2-183A-4E67-8D77-48BF917EC9D8}']
    function ComponentName: string;
  end;

  IYakkoLifecycleAware = interface
    ['{7DA30B3B-5874-4CE4-BDEB-C5C8313734FA}']
    procedure Initialize;
    procedure Shutdown;
    procedure Reset;
  end;

  IYakkoDebuggable = interface
    ['{95D091DE-1575-4AAE-B558-9F8A529DD8F5}']
    function ToDebugString: string;
  end;

  IYakkoCloneable = interface
    ['{0CB4CEC8-3677-4D7B-8BC4-817F0D0B4456}']
    function CloneAsObject: TObject;
  end;

  IYakkoMetadataContainer = interface
    ['{663C605A-3454-48FC-8527-C18D1ED05C64}']
    function GetMetadata: TDictionary<string, string>;
  end;

implementation

end.
