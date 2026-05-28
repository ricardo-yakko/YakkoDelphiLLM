unit uYakkoFullExportsComponent;

{ Registry de exports nativos do backend.
  Responsabilidades:
  - resolver simbolos da DLL
  - expor ponteiros de funcoes com validacao defensiva
  - centralizar superficie de API nativa. }

interface

uses
  System.Classes,
  Winapi.Windows,
  System.SysUtils;

type
  ELlamaWrapperError = class(Exception);

  TYakkoFullExports = class(TComponent)
  private
    FDllPath: string;
    function GetCarregado: Boolean;
    procedure SetDllPath(const Value: string);
  public
    destructor Destroy; override;

    procedure Carregar(const ACaminho: string = '');
    procedure Descarregar;
    function EstaCarregado: Boolean;
  published
    property DllPath: string read FDllPath write SetDllPath;
    property Carregado: Boolean read GetCarregado stored False;
  end;

var
  LlamaDllHandle: HMODULE = 0;
  llama_internal_export_0001: Pointer;
  llama_internal_export_0002: Pointer;
  llama_internal_export_0003: Pointer;
  llama_internal_export_0004: Pointer;
  llama_internal_export_0005: Pointer;
  llama_internal_export_0006: Pointer;
  llama_internal_export_0007: Pointer;
  llama_internal_export_0008: Pointer;
  llama_internal_export_0009: Pointer;
  llama_internal_export_0010: Pointer;
  llama_internal_export_0011: Pointer;
  llama_adapter_get_alora_invocation_tokens: Pointer;
  llama_adapter_get_alora_n_invocation_tokens: Pointer;
  llama_adapter_lora_free: Pointer;
  llama_adapter_lora_init: Pointer;
  llama_adapter_meta_count: Pointer;
  llama_adapter_meta_key_by_index: Pointer;
  llama_adapter_meta_val_str: Pointer;
  llama_adapter_meta_val_str_by_index: Pointer;
  llama_add_bos_token: Pointer;
  llama_add_eos_token: Pointer;
  llama_attach_threadpool: Pointer;
  llama_backend_free: Pointer;
  llama_backend_init: Pointer;
  llama_batch_free: Pointer;
  llama_batch_get_one: Pointer;
  llama_batch_init: Pointer;
  llama_chat_apply_template: Pointer;
  llama_chat_builtin_templates: Pointer;
  llama_context_default_params: Pointer;
  llama_copy_state_data: Pointer;
  llama_decode: Pointer;
  llama_detach_threadpool: Pointer;
  llama_detokenize: Pointer;
  llama_encode: Pointer;
  llama_flash_attn_type_name: Pointer;
  llama_free: Pointer;
  llama_free_model: Pointer;
  llama_get_embeddings: Pointer;
  llama_get_embeddings_ith: Pointer;
  llama_get_embeddings_seq: Pointer;
  llama_get_logits: Pointer;
  llama_get_logits_ith: Pointer;
  llama_get_memory: Pointer;
  llama_get_model: Pointer;
  llama_get_sampled_candidates_count_ith: Pointer;
  llama_get_sampled_candidates_ith: Pointer;
  llama_get_sampled_logits_count_ith: Pointer;
  llama_get_sampled_logits_ith: Pointer;
  llama_get_sampled_probs_count_ith: Pointer;
  llama_get_sampled_probs_ith: Pointer;
  llama_get_sampled_token_ith: Pointer;
  llama_get_state_size: Pointer;
  llama_init_from_model: Pointer;
  llama_load_model_from_file: Pointer;
  llama_load_session_file: Pointer;
  llama_log_get: Pointer;
  llama_log_set: Pointer;
  llama_max_devices: Pointer;
  llama_max_parallel_sequences: Pointer;
  llama_max_tensor_buft_overrides: Pointer;
  llama_memory_can_shift: Pointer;
  llama_memory_clear: Pointer;
  llama_memory_seq_add: Pointer;
  llama_memory_seq_cp: Pointer;
  llama_memory_seq_div: Pointer;
  llama_memory_seq_keep: Pointer;
  llama_memory_seq_pos_max: Pointer;
  llama_memory_seq_pos_min: Pointer;
  llama_memory_seq_rm: Pointer;
  llama_model_chat_template: Pointer;
  llama_model_cls_label: Pointer;
  llama_model_decoder_start_token: Pointer;
  llama_model_default_params: Pointer;
  llama_model_desc: Pointer;
  llama_model_free: Pointer;
  llama_model_get_vocab: Pointer;
  llama_model_has_decoder: Pointer;
  llama_model_has_encoder: Pointer;
  llama_model_init_from_user: Pointer;
  llama_model_is_diffusion: Pointer;
  llama_model_is_hybrid: Pointer;
  llama_model_is_recurrent: Pointer;
  llama_model_load_from_file: Pointer;
  llama_model_load_from_file_ptr: Pointer;
  llama_model_load_from_splits: Pointer;
  llama_model_meta_count: Pointer;
  llama_model_meta_key_by_index: Pointer;
  llama_model_meta_key_str: Pointer;
  llama_model_meta_val_str: Pointer;
  llama_model_meta_val_str_by_index: Pointer;
  llama_model_n_cls_out: Pointer;
  llama_model_n_ctx_train: Pointer;
  llama_model_n_embd: Pointer;
  llama_model_n_embd_inp: Pointer;
  llama_model_n_embd_out: Pointer;
  llama_model_n_head: Pointer;
  llama_model_n_head_kv: Pointer;
  llama_model_n_layer: Pointer;
  llama_model_n_params: Pointer;
  llama_model_n_swa: Pointer;
  llama_model_quantize: Pointer;
  llama_model_quantize_default_params: Pointer;
  llama_model_rope_freq_scale_train: Pointer;
  llama_model_rope_type: Pointer;
  llama_model_save_to_file: Pointer;
  llama_model_size: Pointer;
  llama_n_batch: Pointer;
  llama_n_ctx: Pointer;
  llama_n_ctx_seq: Pointer;
  llama_n_ctx_train: Pointer;
  llama_n_embd: Pointer;
  llama_n_head: Pointer;
  llama_n_layer: Pointer;
  llama_n_seq_max: Pointer;
  llama_n_threads: Pointer;
  llama_n_threads_batch: Pointer;
  llama_n_ubatch: Pointer;
  llama_n_vocab: Pointer;
  llama_new_context_with_model: Pointer;
  llama_numa_init: Pointer;
  llama_opt_epoch: Pointer;
  llama_opt_init: Pointer;
  llama_opt_param_filter_all: Pointer;
  llama_perf_context: Pointer;
  llama_perf_context_print: Pointer;
  llama_perf_context_reset: Pointer;
  llama_perf_sampler: Pointer;
  llama_perf_sampler_print: Pointer;
  llama_perf_sampler_reset: Pointer;
  llama_pooling_type: Pointer;
  llama_print_system_info: Pointer;
  llama_sampler_accept: Pointer;
  llama_sampler_apply: Pointer;
  llama_sampler_chain_add: Pointer;
  llama_sampler_chain_default_params: Pointer;
  llama_sampler_chain_get: Pointer;
  llama_sampler_chain_init: Pointer;
  llama_sampler_chain_n: Pointer;
  llama_sampler_chain_remove: Pointer;
  llama_sampler_clone: Pointer;
  llama_sampler_free: Pointer;
  llama_sampler_get_seed: Pointer;
  llama_sampler_init: Pointer;
  llama_sampler_init_adaptive_p: Pointer;
  llama_sampler_init_dist: Pointer;
  llama_sampler_init_dry: Pointer;
  llama_sampler_init_grammar: Pointer;
  llama_sampler_init_grammar_lazy: Pointer;
  llama_sampler_init_grammar_lazy_patterns: Pointer;
  llama_sampler_init_greedy: Pointer;
  llama_sampler_init_infill: Pointer;
  llama_sampler_init_logit_bias: Pointer;
  llama_sampler_init_min_p: Pointer;
  llama_sampler_init_mirostat: Pointer;
  llama_sampler_init_mirostat_v2: Pointer;
  llama_sampler_init_penalties: Pointer;
  llama_sampler_init_temp: Pointer;
  llama_sampler_init_temp_ext: Pointer;
  llama_sampler_init_top_k: Pointer;
  llama_sampler_init_top_n_sigma: Pointer;
  llama_sampler_init_top_p: Pointer;
  llama_sampler_init_typical: Pointer;
  llama_sampler_init_xtc: Pointer;
  llama_sampler_name: Pointer;
  llama_sampler_reset: Pointer;
  llama_sampler_sample: Pointer;
  llama_save_session_file: Pointer;
  llama_set_abort_callback: Pointer;
  llama_set_adapter_cvec: Pointer;
  llama_set_adapters_lora: Pointer;
  llama_set_causal_attn: Pointer;
  llama_set_embeddings: Pointer;
  llama_set_n_threads: Pointer;
  llama_set_sampler: Pointer;
  llama_set_state_data: Pointer;
  llama_set_warmup: Pointer;
  llama_split_path: Pointer;
  llama_split_prefix: Pointer;
  llama_state_get_data: Pointer;
  llama_state_get_size: Pointer;
  llama_state_load_file: Pointer;
  llama_state_save_file: Pointer;
  llama_state_seq_get_data: Pointer;
  llama_state_seq_get_data_ext: Pointer;
  llama_state_seq_get_size: Pointer;
  llama_state_seq_get_size_ext: Pointer;
  llama_state_seq_load_file: Pointer;
  llama_state_seq_save_file: Pointer;
  llama_state_seq_set_data: Pointer;
  llama_state_seq_set_data_ext: Pointer;
  llama_state_set_data: Pointer;
  llama_supports_gpu_offload: Pointer;
  llama_supports_mlock: Pointer;
  llama_supports_mmap: Pointer;
  llama_supports_rpc: Pointer;
  llama_synchronize: Pointer;
  llama_time_us: Pointer;
  llama_token_bos: Pointer;
  llama_token_cls: Pointer;
  llama_token_eos: Pointer;
  llama_token_eot: Pointer;
  llama_token_fim_mid: Pointer;
  llama_token_fim_pad: Pointer;
  llama_token_fim_pre: Pointer;
  llama_token_fim_rep: Pointer;
  llama_token_fim_sep: Pointer;
  llama_token_fim_suf: Pointer;
  llama_token_get_attr: Pointer;
  llama_token_get_score: Pointer;
  llama_token_get_text: Pointer;
  llama_token_is_control: Pointer;
  llama_token_is_eog: Pointer;
  llama_token_nl: Pointer;
  llama_token_pad: Pointer;
  llama_token_sep: Pointer;
  llama_token_to_piece: Pointer;
  llama_tokenize: Pointer;
  llama_vocab_bos: Pointer;
  llama_vocab_cls: Pointer;
  llama_vocab_eos: Pointer;
  llama_vocab_eot: Pointer;
  llama_vocab_fim_mid: Pointer;
  llama_vocab_fim_pad: Pointer;
  llama_vocab_fim_pre: Pointer;
  llama_vocab_fim_rep: Pointer;
  llama_vocab_fim_sep: Pointer;
  llama_vocab_fim_suf: Pointer;
  llama_vocab_get_add_bos: Pointer;
  llama_vocab_get_add_eos: Pointer;
  llama_vocab_get_add_sep: Pointer;
  llama_vocab_get_attr: Pointer;
  llama_vocab_get_score: Pointer;
  llama_vocab_get_text: Pointer;
  llama_vocab_is_control: Pointer;
  llama_vocab_is_eog: Pointer;
  llama_vocab_mask: Pointer;
  llama_vocab_n_tokens: Pointer;
  llama_vocab_nl: Pointer;
  llama_vocab_pad: Pointer;
  llama_vocab_sep: Pointer;
  llama_vocab_type: Pointer;

procedure LoadLlamaExports(const ADllPath: string);
procedure UnloadLlamaExports;

implementation

destructor TYakkoFullExports.Destroy;
begin
  Descarregar;
  inherited;
end;

procedure TYakkoFullExports.Carregar(const ACaminho: string);
var
  LPath: string;
begin
  LPath := Trim(ACaminho);
  if LPath = '' then
    LPath := Trim(FDllPath);
  if LPath = '' then
    raise ELlamaWrapperError.Create('Informe o caminho da llama.dll.');

  LoadLlamaExports(LPath);
  FDllPath := LPath;
end;

procedure TYakkoFullExports.Descarregar;
begin
  UnloadLlamaExports;
end;

function TYakkoFullExports.EstaCarregado: Boolean;
begin
  Result := GetCarregado;
end;

function TYakkoFullExports.GetCarregado: Boolean;
begin
  Result := LlamaDllHandle <> 0;
end;

procedure TYakkoFullExports.SetDllPath(const Value: string);
begin
  FDllPath := Trim(Value);
end;

function LoadSymbol(const AName: AnsiString): Pointer;
begin
  Result := GetProcAddress(LlamaDllHandle, PAnsiChar(AName));
  if not Assigned(Result) then
    raise ELlamaWrapperError.CreateFmt('Export nao encontrado: %s', [string(AName)]);
end;

procedure LoadLlamaExports(const ADllPath: string);
var
  LErr: Cardinal;
  LDllDir: string;
begin
  if LlamaDllHandle <> 0 then
    Exit;

  LDllDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ADllPath));
  if LDllDir <> '' then
    SetDllDirectory(PChar(LDllDir));

  LlamaDllHandle := LoadLibrary(PChar(ADllPath));
  if LlamaDllHandle = 0 then
  begin
    LErr := GetLastError;
    raise ELlamaWrapperError.CreateFmt('Nao foi possivel carregar a DLL: %s (WinErr=%d: %s)', [ADllPath, LErr, SysErrorMessage(LErr)]);
  end;

  llama_internal_export_0001 := LoadSymbol('?llama_ftype_get_default_type@@YA?AW4ggml_type@@W4llama_ftype@@@Z');
  llama_internal_export_0002 := LoadSymbol('?llama_get_memory_breakdown@@YA?AV?$map@PEAUggml_backend_buffer_type@@Ullama_memory_breakdown_data@@U?$less@PEAUggml_backend_buffer_type@@@std@@V?$allocator@U?$pair@QEAUggml_backend_buffer_type@@Ullama_memory_breakdown_data@@@std@@@4@@std@@PEBUllama_context@@@Z');
  llama_internal_export_0003 := LoadSymbol('?llama_graph_reserve@@YAPEAUggml_cgraph@@PEAUllama_context@@III@Z');
  llama_internal_export_0004 := LoadSymbol('?llama_model_get_device@@YAPEAUggml_backend_device@@PEBUllama_model@@H@Z');
  llama_internal_export_0005 := LoadSymbol('?llama_model_n_devices@@YAHPEBUllama_model@@@Z');
  llama_internal_export_0006 := LoadSymbol('?llama_model_n_expert@@YAHPEBUllama_model@@@Z');
  llama_internal_export_0007 := LoadSymbol('?llama_quant_compute_types@@YAXPEAUquantize_state_impl@@W4llama_ftype@@PEAPEAUggml_tensor@@PEAW4ggml_type@@_K@Z');
  llama_internal_export_0008 := LoadSymbol('?llama_quant_free@@YAXPEAUquantize_state_impl@@@Z');
  llama_internal_export_0009 := LoadSymbol('?llama_quant_init@@YAPEAUquantize_state_impl@@PEBUllama_model@@PEBUllama_model_quantize_params@@@Z');
  llama_internal_export_0010 := LoadSymbol('?llama_quant_model_from_metadata@@YAPEAUllama_model@@PEBUllama_quant_model_desc@@@Z');
  llama_internal_export_0011 := LoadSymbol('?llama_quant_tensor_allows_quantization@@YA_NPEBUquantize_state_impl@@PEBUggml_tensor@@@Z');
  llama_adapter_get_alora_invocation_tokens := LoadSymbol('llama_adapter_get_alora_invocation_tokens');
  llama_adapter_get_alora_n_invocation_tokens := LoadSymbol('llama_adapter_get_alora_n_invocation_tokens');
  llama_adapter_lora_free := LoadSymbol('llama_adapter_lora_free');
  llama_adapter_lora_init := LoadSymbol('llama_adapter_lora_init');
  llama_adapter_meta_count := LoadSymbol('llama_adapter_meta_count');
  llama_adapter_meta_key_by_index := LoadSymbol('llama_adapter_meta_key_by_index');
  llama_adapter_meta_val_str := LoadSymbol('llama_adapter_meta_val_str');
  llama_adapter_meta_val_str_by_index := LoadSymbol('llama_adapter_meta_val_str_by_index');
  llama_add_bos_token := LoadSymbol('llama_add_bos_token');
  llama_add_eos_token := LoadSymbol('llama_add_eos_token');
  llama_attach_threadpool := LoadSymbol('llama_attach_threadpool');
  llama_backend_free := LoadSymbol('llama_backend_free');
  llama_backend_init := LoadSymbol('llama_backend_init');
  llama_batch_free := LoadSymbol('llama_batch_free');
  llama_batch_get_one := LoadSymbol('llama_batch_get_one');
  llama_batch_init := LoadSymbol('llama_batch_init');
  llama_chat_apply_template := LoadSymbol('llama_chat_apply_template');
  llama_chat_builtin_templates := LoadSymbol('llama_chat_builtin_templates');
  llama_context_default_params := LoadSymbol('llama_context_default_params');
  llama_copy_state_data := LoadSymbol('llama_copy_state_data');
  llama_decode := LoadSymbol('llama_decode');
  llama_detach_threadpool := LoadSymbol('llama_detach_threadpool');
  llama_detokenize := LoadSymbol('llama_detokenize');
  llama_encode := LoadSymbol('llama_encode');
  llama_flash_attn_type_name := LoadSymbol('llama_flash_attn_type_name');
  llama_free := LoadSymbol('llama_free');
  llama_free_model := LoadSymbol('llama_free_model');
  llama_get_embeddings := LoadSymbol('llama_get_embeddings');
  llama_get_embeddings_ith := LoadSymbol('llama_get_embeddings_ith');
  llama_get_embeddings_seq := LoadSymbol('llama_get_embeddings_seq');
  llama_get_logits := LoadSymbol('llama_get_logits');
  llama_get_logits_ith := LoadSymbol('llama_get_logits_ith');
  llama_get_memory := LoadSymbol('llama_get_memory');
  llama_get_model := LoadSymbol('llama_get_model');
  llama_get_sampled_candidates_count_ith := LoadSymbol('llama_get_sampled_candidates_count_ith');
  llama_get_sampled_candidates_ith := LoadSymbol('llama_get_sampled_candidates_ith');
  llama_get_sampled_logits_count_ith := LoadSymbol('llama_get_sampled_logits_count_ith');
  llama_get_sampled_logits_ith := LoadSymbol('llama_get_sampled_logits_ith');
  llama_get_sampled_probs_count_ith := LoadSymbol('llama_get_sampled_probs_count_ith');
  llama_get_sampled_probs_ith := LoadSymbol('llama_get_sampled_probs_ith');
  llama_get_sampled_token_ith := LoadSymbol('llama_get_sampled_token_ith');
  llama_get_state_size := LoadSymbol('llama_get_state_size');
  llama_init_from_model := LoadSymbol('llama_init_from_model');
  llama_load_model_from_file := LoadSymbol('llama_load_model_from_file');
  llama_load_session_file := LoadSymbol('llama_load_session_file');
  llama_log_get := LoadSymbol('llama_log_get');
  llama_log_set := LoadSymbol('llama_log_set');
  llama_max_devices := LoadSymbol('llama_max_devices');
  llama_max_parallel_sequences := LoadSymbol('llama_max_parallel_sequences');
  llama_max_tensor_buft_overrides := LoadSymbol('llama_max_tensor_buft_overrides');
  llama_memory_can_shift := LoadSymbol('llama_memory_can_shift');
  llama_memory_clear := LoadSymbol('llama_memory_clear');
  llama_memory_seq_add := LoadSymbol('llama_memory_seq_add');
  llama_memory_seq_cp := LoadSymbol('llama_memory_seq_cp');
  llama_memory_seq_div := LoadSymbol('llama_memory_seq_div');
  llama_memory_seq_keep := LoadSymbol('llama_memory_seq_keep');
  llama_memory_seq_pos_max := LoadSymbol('llama_memory_seq_pos_max');
  llama_memory_seq_pos_min := LoadSymbol('llama_memory_seq_pos_min');
  llama_memory_seq_rm := LoadSymbol('llama_memory_seq_rm');
  llama_model_chat_template := LoadSymbol('llama_model_chat_template');
  llama_model_cls_label := LoadSymbol('llama_model_cls_label');
  llama_model_decoder_start_token := LoadSymbol('llama_model_decoder_start_token');
  llama_model_default_params := LoadSymbol('llama_model_default_params');
  llama_model_desc := LoadSymbol('llama_model_desc');
  llama_model_free := LoadSymbol('llama_model_free');
  llama_model_get_vocab := LoadSymbol('llama_model_get_vocab');
  llama_model_has_decoder := LoadSymbol('llama_model_has_decoder');
  llama_model_has_encoder := LoadSymbol('llama_model_has_encoder');
  llama_model_init_from_user := LoadSymbol('llama_model_init_from_user');
  llama_model_is_diffusion := LoadSymbol('llama_model_is_diffusion');
  llama_model_is_hybrid := LoadSymbol('llama_model_is_hybrid');
  llama_model_is_recurrent := LoadSymbol('llama_model_is_recurrent');
  llama_model_load_from_file := LoadSymbol('llama_model_load_from_file');
  llama_model_load_from_file_ptr := LoadSymbol('llama_model_load_from_file_ptr');
  llama_model_load_from_splits := LoadSymbol('llama_model_load_from_splits');
  llama_model_meta_count := LoadSymbol('llama_model_meta_count');
  llama_model_meta_key_by_index := LoadSymbol('llama_model_meta_key_by_index');
  llama_model_meta_key_str := LoadSymbol('llama_model_meta_key_str');
  llama_model_meta_val_str := LoadSymbol('llama_model_meta_val_str');
  llama_model_meta_val_str_by_index := LoadSymbol('llama_model_meta_val_str_by_index');
  llama_model_n_cls_out := LoadSymbol('llama_model_n_cls_out');
  llama_model_n_ctx_train := LoadSymbol('llama_model_n_ctx_train');
  llama_model_n_embd := LoadSymbol('llama_model_n_embd');
  llama_model_n_embd_inp := LoadSymbol('llama_model_n_embd_inp');
  llama_model_n_embd_out := LoadSymbol('llama_model_n_embd_out');
  llama_model_n_head := LoadSymbol('llama_model_n_head');
  llama_model_n_head_kv := LoadSymbol('llama_model_n_head_kv');
  llama_model_n_layer := LoadSymbol('llama_model_n_layer');
  llama_model_n_params := LoadSymbol('llama_model_n_params');
  llama_model_n_swa := LoadSymbol('llama_model_n_swa');
  llama_model_quantize := LoadSymbol('llama_model_quantize');
  llama_model_quantize_default_params := LoadSymbol('llama_model_quantize_default_params');
  llama_model_rope_freq_scale_train := LoadSymbol('llama_model_rope_freq_scale_train');
  llama_model_rope_type := LoadSymbol('llama_model_rope_type');
  llama_model_save_to_file := LoadSymbol('llama_model_save_to_file');
  llama_model_size := LoadSymbol('llama_model_size');
  llama_n_batch := LoadSymbol('llama_n_batch');
  llama_n_ctx := LoadSymbol('llama_n_ctx');
  llama_n_ctx_seq := LoadSymbol('llama_n_ctx_seq');
  llama_n_ctx_train := LoadSymbol('llama_n_ctx_train');
  llama_n_embd := LoadSymbol('llama_n_embd');
  llama_n_head := LoadSymbol('llama_n_head');
  llama_n_layer := LoadSymbol('llama_n_layer');
  llama_n_seq_max := LoadSymbol('llama_n_seq_max');
  llama_n_threads := LoadSymbol('llama_n_threads');
  llama_n_threads_batch := LoadSymbol('llama_n_threads_batch');
  llama_n_ubatch := LoadSymbol('llama_n_ubatch');
  llama_n_vocab := LoadSymbol('llama_n_vocab');
  llama_new_context_with_model := LoadSymbol('llama_new_context_with_model');
  llama_numa_init := LoadSymbol('llama_numa_init');
  llama_opt_epoch := LoadSymbol('llama_opt_epoch');
  llama_opt_init := LoadSymbol('llama_opt_init');
  llama_opt_param_filter_all := LoadSymbol('llama_opt_param_filter_all');
  llama_perf_context := LoadSymbol('llama_perf_context');
  llama_perf_context_print := LoadSymbol('llama_perf_context_print');
  llama_perf_context_reset := LoadSymbol('llama_perf_context_reset');
  llama_perf_sampler := LoadSymbol('llama_perf_sampler');
  llama_perf_sampler_print := LoadSymbol('llama_perf_sampler_print');
  llama_perf_sampler_reset := LoadSymbol('llama_perf_sampler_reset');
  llama_pooling_type := LoadSymbol('llama_pooling_type');
  llama_print_system_info := LoadSymbol('llama_print_system_info');
  llama_sampler_accept := LoadSymbol('llama_sampler_accept');
  llama_sampler_apply := LoadSymbol('llama_sampler_apply');
  llama_sampler_chain_add := LoadSymbol('llama_sampler_chain_add');
  llama_sampler_chain_default_params := LoadSymbol('llama_sampler_chain_default_params');
  llama_sampler_chain_get := LoadSymbol('llama_sampler_chain_get');
  llama_sampler_chain_init := LoadSymbol('llama_sampler_chain_init');
  llama_sampler_chain_n := LoadSymbol('llama_sampler_chain_n');
  llama_sampler_chain_remove := LoadSymbol('llama_sampler_chain_remove');
  llama_sampler_clone := LoadSymbol('llama_sampler_clone');
  llama_sampler_free := LoadSymbol('llama_sampler_free');
  llama_sampler_get_seed := LoadSymbol('llama_sampler_get_seed');
  llama_sampler_init := LoadSymbol('llama_sampler_init');
  llama_sampler_init_adaptive_p := LoadSymbol('llama_sampler_init_adaptive_p');
  llama_sampler_init_dist := LoadSymbol('llama_sampler_init_dist');
  llama_sampler_init_dry := LoadSymbol('llama_sampler_init_dry');
  llama_sampler_init_grammar := LoadSymbol('llama_sampler_init_grammar');
  llama_sampler_init_grammar_lazy := LoadSymbol('llama_sampler_init_grammar_lazy');
  llama_sampler_init_grammar_lazy_patterns := LoadSymbol('llama_sampler_init_grammar_lazy_patterns');
  llama_sampler_init_greedy := LoadSymbol('llama_sampler_init_greedy');
  llama_sampler_init_infill := LoadSymbol('llama_sampler_init_infill');
  llama_sampler_init_logit_bias := LoadSymbol('llama_sampler_init_logit_bias');
  llama_sampler_init_min_p := LoadSymbol('llama_sampler_init_min_p');
  llama_sampler_init_mirostat := LoadSymbol('llama_sampler_init_mirostat');
  llama_sampler_init_mirostat_v2 := LoadSymbol('llama_sampler_init_mirostat_v2');
  llama_sampler_init_penalties := LoadSymbol('llama_sampler_init_penalties');
  llama_sampler_init_temp := LoadSymbol('llama_sampler_init_temp');
  llama_sampler_init_temp_ext := LoadSymbol('llama_sampler_init_temp_ext');
  llama_sampler_init_top_k := LoadSymbol('llama_sampler_init_top_k');
  llama_sampler_init_top_n_sigma := LoadSymbol('llama_sampler_init_top_n_sigma');
  llama_sampler_init_top_p := LoadSymbol('llama_sampler_init_top_p');
  llama_sampler_init_typical := LoadSymbol('llama_sampler_init_typical');
  llama_sampler_init_xtc := LoadSymbol('llama_sampler_init_xtc');
  llama_sampler_name := LoadSymbol('llama_sampler_name');
  llama_sampler_reset := LoadSymbol('llama_sampler_reset');
  llama_sampler_sample := LoadSymbol('llama_sampler_sample');
  llama_save_session_file := LoadSymbol('llama_save_session_file');
  llama_set_abort_callback := LoadSymbol('llama_set_abort_callback');
  llama_set_adapter_cvec := LoadSymbol('llama_set_adapter_cvec');
  llama_set_adapters_lora := LoadSymbol('llama_set_adapters_lora');
  llama_set_causal_attn := LoadSymbol('llama_set_causal_attn');
  llama_set_embeddings := LoadSymbol('llama_set_embeddings');
  llama_set_n_threads := LoadSymbol('llama_set_n_threads');
  llama_set_sampler := LoadSymbol('llama_set_sampler');
  llama_set_state_data := LoadSymbol('llama_set_state_data');
  llama_set_warmup := LoadSymbol('llama_set_warmup');
  llama_split_path := LoadSymbol('llama_split_path');
  llama_split_prefix := LoadSymbol('llama_split_prefix');
  llama_state_get_data := LoadSymbol('llama_state_get_data');
  llama_state_get_size := LoadSymbol('llama_state_get_size');
  llama_state_load_file := LoadSymbol('llama_state_load_file');
  llama_state_save_file := LoadSymbol('llama_state_save_file');
  llama_state_seq_get_data := LoadSymbol('llama_state_seq_get_data');
  llama_state_seq_get_data_ext := LoadSymbol('llama_state_seq_get_data_ext');
  llama_state_seq_get_size := LoadSymbol('llama_state_seq_get_size');
  llama_state_seq_get_size_ext := LoadSymbol('llama_state_seq_get_size_ext');
  llama_state_seq_load_file := LoadSymbol('llama_state_seq_load_file');
  llama_state_seq_save_file := LoadSymbol('llama_state_seq_save_file');
  llama_state_seq_set_data := LoadSymbol('llama_state_seq_set_data');
  llama_state_seq_set_data_ext := LoadSymbol('llama_state_seq_set_data_ext');
  llama_state_set_data := LoadSymbol('llama_state_set_data');
  llama_supports_gpu_offload := LoadSymbol('llama_supports_gpu_offload');
  llama_supports_mlock := LoadSymbol('llama_supports_mlock');
  llama_supports_mmap := LoadSymbol('llama_supports_mmap');
  llama_supports_rpc := LoadSymbol('llama_supports_rpc');
  llama_synchronize := LoadSymbol('llama_synchronize');
  llama_time_us := LoadSymbol('llama_time_us');
  llama_token_bos := LoadSymbol('llama_token_bos');
  llama_token_cls := LoadSymbol('llama_token_cls');
  llama_token_eos := LoadSymbol('llama_token_eos');
  llama_token_eot := LoadSymbol('llama_token_eot');
  llama_token_fim_mid := LoadSymbol('llama_token_fim_mid');
  llama_token_fim_pad := LoadSymbol('llama_token_fim_pad');
  llama_token_fim_pre := LoadSymbol('llama_token_fim_pre');
  llama_token_fim_rep := LoadSymbol('llama_token_fim_rep');
  llama_token_fim_sep := LoadSymbol('llama_token_fim_sep');
  llama_token_fim_suf := LoadSymbol('llama_token_fim_suf');
  llama_token_get_attr := LoadSymbol('llama_token_get_attr');
  llama_token_get_score := LoadSymbol('llama_token_get_score');
  llama_token_get_text := LoadSymbol('llama_token_get_text');
  llama_token_is_control := LoadSymbol('llama_token_is_control');
  llama_token_is_eog := LoadSymbol('llama_token_is_eog');
  llama_token_nl := LoadSymbol('llama_token_nl');
  llama_token_pad := LoadSymbol('llama_token_pad');
  llama_token_sep := LoadSymbol('llama_token_sep');
  llama_token_to_piece := LoadSymbol('llama_token_to_piece');
  llama_tokenize := LoadSymbol('llama_tokenize');
  llama_vocab_bos := LoadSymbol('llama_vocab_bos');
  llama_vocab_cls := LoadSymbol('llama_vocab_cls');
  llama_vocab_eos := LoadSymbol('llama_vocab_eos');
  llama_vocab_eot := LoadSymbol('llama_vocab_eot');
  llama_vocab_fim_mid := LoadSymbol('llama_vocab_fim_mid');
  llama_vocab_fim_pad := LoadSymbol('llama_vocab_fim_pad');
  llama_vocab_fim_pre := LoadSymbol('llama_vocab_fim_pre');
  llama_vocab_fim_rep := LoadSymbol('llama_vocab_fim_rep');
  llama_vocab_fim_sep := LoadSymbol('llama_vocab_fim_sep');
  llama_vocab_fim_suf := LoadSymbol('llama_vocab_fim_suf');
  llama_vocab_get_add_bos := LoadSymbol('llama_vocab_get_add_bos');
  llama_vocab_get_add_eos := LoadSymbol('llama_vocab_get_add_eos');
  llama_vocab_get_add_sep := LoadSymbol('llama_vocab_get_add_sep');
  llama_vocab_get_attr := LoadSymbol('llama_vocab_get_attr');
  llama_vocab_get_score := LoadSymbol('llama_vocab_get_score');
  llama_vocab_get_text := LoadSymbol('llama_vocab_get_text');
  llama_vocab_is_control := LoadSymbol('llama_vocab_is_control');
  llama_vocab_is_eog := LoadSymbol('llama_vocab_is_eog');
  llama_vocab_mask := LoadSymbol('llama_vocab_mask');
  llama_vocab_n_tokens := LoadSymbol('llama_vocab_n_tokens');
  llama_vocab_nl := LoadSymbol('llama_vocab_nl');
  llama_vocab_pad := LoadSymbol('llama_vocab_pad');
  llama_vocab_sep := LoadSymbol('llama_vocab_sep');
  llama_vocab_type := LoadSymbol('llama_vocab_type');
end;

procedure UnloadLlamaExports;
begin
  if LlamaDllHandle <> 0 then
  begin
    FreeLibrary(LlamaDllHandle);
    LlamaDllHandle := 0;
  end;
end;

initialization
  System.Classes.RegisterClass(TYakkoFullExports);

end.

