unit Yakko.Runtime.Metadata;

{ Runtime metadata standardization layer for YakkoDelphiLLM.

  Architectural intent:
  - centralize official metadata keys used across runtime layers;
  - prevent string chaos and key drift between components;
  - keep metadata deterministic and auditable without hidden conventions.

  This unit intentionally provides constants and helper methods only.
  No reflection, no auto-discovery, no dynamic schema loading. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRuntimeMetadataKeys = class
  public
    const Capabilities = 'capabilities';
    const SupportedModels = 'supported_models';
    const SupportedProviders = 'supported_providers';
    const SupportedTemplates = 'supported_templates';
    const SupportedPipelines = 'supported_pipelines';

    const RequiresModelCapabilities = 'requires_model_capabilities';
    const RequiresProviderCapabilities = 'requires_provider_capabilities';
    const RequiresTemplateCapabilities = 'requires_template_capabilities';
    const RequiresPipelineCapabilities = 'requires_pipeline_capabilities';

    const Name = 'name';
    const ItemName = 'item_name';

    const ModelName = 'model_name';
    const ProviderName = 'provider_name';
    const TemplateName = 'template_name';
    const PipelineName = 'pipeline_name';
  end;

  TYakkoRuntimeMetadata = class
  public
    class function GetValueOrEmpty(AMetadata: TDictionary<string, string>; const AKey: string): string; static;
    class function HasKey(AMetadata: TDictionary<string, string>; const AKey: string): Boolean; static;
    class procedure SetValue(AMetadata: TDictionary<string, string>; const AKey, AValue: string); static;
  end;

implementation

{ TYakkoRuntimeMetadata }

class function TYakkoRuntimeMetadata.GetValueOrEmpty(
  AMetadata: TDictionary<string, string>; const AKey: string): string;
begin
  Result := '';
  if Assigned(AMetadata) and AMetadata.ContainsKey(AKey) then
    Result := Trim(AMetadata[AKey]);
end;

class function TYakkoRuntimeMetadata.HasKey(
  AMetadata: TDictionary<string, string>; const AKey: string): Boolean;
begin
  Result := Assigned(AMetadata) and AMetadata.ContainsKey(AKey);
end;

class procedure TYakkoRuntimeMetadata.SetValue(
  AMetadata: TDictionary<string, string>; const AKey, AValue: string);
begin
  if not Assigned(AMetadata) then
    raise EArgumentNilException.Create('AMetadata must be assigned.');

  AMetadata.AddOrSetValue(AKey, AValue);
end;

end.
