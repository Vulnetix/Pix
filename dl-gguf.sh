#!/usr/bin/env bash

# Creates Ollama models from Unsloth's improved LoRA finetuned GPT-OSS 20B in GGUF format
# Reference: https://colab.research.google.com/github/unslothai/notebooks/blob/main/nb/GPT_OSS_MXFP4_(20B)-Inference.ipynb

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/.dl-gguf-config"
readonly LOG_FILE="${SCRIPT_DIR}/dl-gguf.log"

readonly VALID_QUANTS="Q2_K Q3_K_S Q3_K_M Q3_K_L Q4_K_S Q4_K_M Q5_K_S Q5_K_M Q6_K Q8_0 F16 F32"

get_quant_description() {
    case "$1" in
        Q2_K) echo "smallest, extreme quality loss - not recommended" ;;
        Q3_K_S) echo "very small, very high quality loss" ;;
        Q3_K_M) echo "very small, very high quality loss" ;;
        Q3_K_L) echo "small, substantial quality loss" ;;
        Q4_K_S) echo "small, significant quality loss" ;;
        Q4_K_M) echo "medium, balanced quality - recommended" ;;
        Q5_K_S) echo "large, low quality loss - recommended" ;;
        Q5_K_M) echo "large, very low quality loss - recommended" ;;
        Q6_K) echo "very large, extremely low quality loss" ;;
        Q8_0) echo "very large, extremely low quality loss - not recommended" ;;
        F16) echo "extremely large, virtually no quality loss - not recommended" ;;
        F32) echo "absolutely huge, lossless - not recommended" ;;
        *) echo "" ;;
    esac
}

readonly DEFAULT_QUANTS="Q6_K"
readonly DEFAULT_HF_SOURCE="unsloth/gpt-oss-20b-GGUF"
readonly DEFAULT_MODEL_BASENAME="ReBort"
readonly DEFAULT_PYTHON_VERSION="3.13"
readonly DEFAULT_REPEAT_PENALTY="1.1"
readonly DEFAULT_PROVIDER="openai"
readonly DEFAULT_MODEL=""
readonly DEFAULT_SIZE=""

readonly GPT_OSS_PROVIDERS="openai unsloth"

quants="${DEFAULT_QUANTS}"
hf_source="${DEFAULT_HF_SOURCE}"
model_basename="${DEFAULT_MODEL_BASENAME}"
python_version="${DEFAULT_PYTHON_VERSION}"
repeat_penalty="${DEFAULT_REPEAT_PENALTY}"
provider="${DEFAULT_PROVIDER}"
model_name="${DEFAULT_MODEL}"
model_size="${DEFAULT_SIZE}"
verbose=false
dry_run=false
force=false
log_level="INFO"
model_source=""
model_target=""
model_file=""
config_file="${DEFAULT_CONFIG_FILE}"

# CLI tracking variables to prevent config overrides
cli_quants_set=""
cli_hf_source_set=""
cli_model_basename_set=""
cli_python_version_set=""
cli_repeat_penalty_set=""
cli_provider_set=""
cli_model_name_set=""
cli_model_size_set=""
cli_verbose_set=""
cli_dry_run_set=""
cli_force_set=""
cli_log_level_set=""
cli_config_file_set=""

log() {
    local level="${1}"
    local message="${2}"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "${level}" in
        ERROR)
            echo "[${timestamp}] ${level}: ${message}" >&2
            ;;
        WARN)
            if [[ "${log_level}" != "QUIET" ]]; then
                echo "[${timestamp}] ${level}: ${message}" >&2
            fi
            ;;
        INFO)
            if [[ "${log_level}" != "QUIET" ]]; then
                echo "[${timestamp}] ${level}: ${message}"
            fi
            ;;
        DEBUG)
            if [[ "${verbose}" == true && "${log_level}" != "QUIET" ]]; then
                echo "[${timestamp}] ${level}: ${message}"
            fi
            ;;
    esac
    
    echo "[${timestamp}] ${level}: ${message}" >> "${LOG_FILE}"
}

error_exit() {
    local message="${1:-Unknown error}"
    log "ERROR" "${message}"
    exit 1
}

validate_quant() {
    local quant="${1}"
    
    if [[ " ${VALID_QUANTS} " == *" ${quant} "* ]]; then
        return 0
    else
        error_exit "Invalid quantization '${quant}'. Valid options: ${VALID_QUANTS}"
    fi
}

validate_provider() {
    local provider="${1}"
    
    if [[ " ${GPT_OSS_PROVIDERS} " == *" ${provider} "* ]]; then
        return 0
    else
        error_exit "Invalid provider '${provider}'. Valid options: ${GPT_OSS_PROVIDERS}"
    fi
}

detect_model_info() {
    local source="${1}"
    
    log "DEBUG" "Detecting model info from source: ${source}"
    
    if [[ "${source}" =~ ([^/]+)/([^-/]+)(-([0-9]+[bB]))?(-GGUF)?$ ]]; then
        local detected_user="${BASH_REMATCH[1]}"
        local detected_model="${BASH_REMATCH[2]}"
        local detected_size="${BASH_REMATCH[4]}"
        
        if [[ -z "${model_name}" ]]; then
            model_name="${detected_model}"
        fi
        
        if [[ -z "${model_size}" && -n "${detected_size}" ]]; then
            model_size="${detected_size}"
        fi
        
        if [[ "${detected_model}" == "gpt-oss" || "${detected_model}" == "gpt_oss" ]]; then
            if [[ "${provider}" == "auto" ]]; then
                if [[ "${detected_user}" == "openai" ]]; then
                    provider="openai"
                elif [[ "${detected_user}" == "unsloth" ]]; then
                    provider="unsloth"
                fi
            fi
        fi
        
        log "DEBUG" "Detected - User: ${detected_user}, Model: ${model_name}, Size: ${model_size}, Provider: ${provider}"
    fi
}

resolve_gptoss_source() {
    local target_provider="${1}"
    local target_size="${2:-20b}"
    
    case "${target_provider}" in
        openai)
            echo "openai/gpt-oss-${target_size}"
            ;;
        unsloth)
            echo "unsloth/gpt-oss-${target_size}-GGUF"
            ;;
        *)
            error_exit "Unknown GPT-OSS provider: ${target_provider}"
            ;;
    esac
}

construct_gguf_filename() {
    local model="${1}"
    local size="${2}"
    local quant="${3}"
    local source="${4}"
    
    log "DEBUG" "Constructing GGUF filename for model=${model}, size=${size}, quant=${quant}"
    
    if [[ "${model}" == "gpt-oss" || "${model}" == "gpt_oss" ]]; then
        echo "gpt-oss-${size:-20b}-${quant}.gguf"
    else
        if [[ "${source}" =~ GGUF$ ]]; then
            if [[ -n "${size}" ]]; then
                echo "${model}-${size}-${quant}.gguf"
            else
                echo "${model}-${quant}.gguf"
            fi
        else
            echo "${model}.${quant}.gguf"
        fi
    fi
}

check_dependencies() {
    log "DEBUG" "Checking dependencies..."
    
    local deps=("uv" "ollama" "sed" "cat" "wget" "cp")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" >/dev/null 2>&1; then
            missing_deps+=("${dep}")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing dependencies: ${missing_deps[*]}"
    fi
    
    log "DEBUG" "All dependencies found"
}

check_required_files() {
    log "DEBUG" "Checking required files..."
    
    local required_files=("Modelfile.base" "SYSTEM.md")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
            missing_files+=("${file}")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        error_exit "Missing required files: ${missing_files[*]}"
    fi
    
    log "DEBUG" "All required files found"
}

load_config() {
    if [[ -f "${config_file}" ]]; then
        log "DEBUG" "Loading configuration from ${config_file}"
        
        while IFS='=' read -r key value; do
            [[ "${key}" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key}" ]] && continue
            
            # Trim whitespace from key and value
            key=$(echo "${key}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
            value=$(echo "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            case "${key}" in
                quants) 
                    [[ -z "${cli_quants_set:-}" ]] && quants="${value}"
                    ;;
                hf_source) 
                    [[ -z "${cli_hf_source_set:-}" ]] && hf_source="${value}" 
                    ;;
                model_basename) 
                    [[ -z "${cli_model_basename_set:-}" ]] && model_basename="${value}" 
                    ;;
                python_version) 
                    [[ -z "${cli_python_version_set:-}" ]] && python_version="${value}" 
                    ;;
                repeat_penalty) 
                    [[ -z "${cli_repeat_penalty_set:-}" ]] && repeat_penalty="${value}" 
                    ;;
                log_level) 
                    [[ -z "${cli_log_level_set:-}" ]] && log_level="${value}" 
                    ;;
                provider) 
                    [[ -z "${cli_provider_set:-}" ]] && provider="${value}" 
                    ;;
                model_name) 
                    [[ -z "${cli_model_name_set:-}" ]] && model_name="${value}" 
                    ;;
                model_size) 
                    [[ -z "${cli_model_size_set:-}" ]] && model_size="${value}" 
                    ;;
                config_file) 
                    [[ -z "${cli_config_file_set:-}" ]] && config_file="${value}" 
                    ;;
                verbose) 
                    if [[ -z "${cli_verbose_set:-}" ]]; then
                        case "${value}" in
                            true|TRUE|1|yes|YES) verbose=true ;;
                            false|FALSE|0|no|NO) verbose=false ;;
                            *) log "WARN" "Invalid verbose value in config: ${value}, using false" ;;
                        esac
                    fi
                    ;;
                dry_run) 
                    if [[ -z "${cli_dry_run_set:-}" ]]; then
                        case "${value}" in
                            true|TRUE|1|yes|YES) dry_run=true ;;
                            false|FALSE|0|no|NO) dry_run=false ;;
                            *) log "WARN" "Invalid dry_run value in config: ${value}, using false" ;;
                        esac
                    fi
                    ;;
                force) 
                    if [[ -z "${cli_force_set:-}" ]]; then
                        case "${value}" in
                            true|TRUE|1|yes|YES) force=true ;;
                            false|FALSE|0|no|NO) force=false ;;
                            *) log "WARN" "Invalid force value in config: ${value}, using false" ;;
                        esac
                    fi
                    ;;
                *) 
                    log "DEBUG" "Unknown configuration key: ${key}" 
                    ;;
            esac
        done < "${config_file}"
        
        log "DEBUG" "Configuration loaded successfully"
    else
        log "DEBUG" "Configuration file ${config_file} not found, using defaults"
    fi
}

show_help() {
    cat << EOF
${SCRIPT_NAME} - Universal HuggingFace GGUF Model Creation Script

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

DESCRIPTION:
    Downloads GGUF models from HuggingFace and creates Ollama models.
    Supports any HuggingFace GGUF repository with special handling for GPT-OSS models.

OPTIONS:
    -q, --quants QUANT          Quantization level (default: ${DEFAULT_QUANTS})
    -s, --source SOURCE         HuggingFace source repo (default: ${DEFAULT_HF_SOURCE})
    -m, --model MODEL           Model name (auto-detected from source if not specified)
    -z, --size SIZE             Model size (auto-detected from source if not specified)
    -P, --provider PROVIDER     For GPT-OSS: openai, unsloth (default: ${DEFAULT_PROVIDER})
    -b, --basename BASENAME     Model basename (default: ${DEFAULT_MODEL_BASENAME})
    -p, --python VERSION        Python version (default: ${DEFAULT_PYTHON_VERSION})
    -r, --repeat-penalty NUM    Repeat penalty (default: ${DEFAULT_REPEAT_PENALTY})
    -c, --config FILE          Configuration file (default: ${DEFAULT_CONFIG_FILE})
    -l, --log-level LEVEL      Log level: DEBUG, INFO, WARN, ERROR, QUIET (default: INFO)
    -v, --verbose              Enable verbose output
    -S, --silent               Disable all output except errors (same as --log-level QUIET)
    -n, --dry-run              Show what would be done without executing
    -f, --force                Force overwrite existing files
    -h, --help                 Show this help message
    --list-quants              List available quantization levels
    --list-providers           List available providers for GPT-OSS
    --generate-config          Generate sample configuration file

QUANTIZATION LEVELS:
EOF
    
    for quant in ${VALID_QUANTS}; do
        if [[ "${quant}" != "" ]]; then
            printf "    %-8s %s\\n" "${quant}" "$(get_quant_description "${quant}")"
        fi
    done
    
    cat << EOF

EXAMPLES:
    # Use GPT-OSS with specific provider
    ${SCRIPT_NAME} --provider openai --size 20b --quants Q4_K_M
    
    # Use any HuggingFace GGUF model
    ${SCRIPT_NAME} --source microsoft/DialoGPT-medium-GGUF --quants Q4_K_M
    
    # Auto-detect everything from source
    ${SCRIPT_NAME} --source unsloth/llama-2-7b-GGUF --basename Llama2-7B
    
    # Dry run with verbose output
    ${SCRIPT_NAME} --dry-run --verbose
    
    # Generate config file
    ${SCRIPT_NAME} --generate-config > .gptoss-config

FILES:
    Configuration: ${DEFAULT_CONFIG_FILE}
    Log file:      ${LOG_FILE}
    Required:      Modelfile.base, SYSTEM.md

For more information, visit:
https://colab.research.google.com/github/unslothai/notebooks/blob/main/nb/GPT_OSS_MXFP4_(20B)-Inference.ipynb
EOF
}

list_quants() {
    echo "Available quantization levels:"
    for quant in ${VALID_QUANTS}; do
        if [[ "${quant}" != "" ]]; then
            printf "  %-8s - %s\\n" "${quant}" "$(get_quant_description "${quant}")"
        fi
    done
}

list_providers() {
    echo "Available providers for GPT-OSS models:"
    for provider in ${GPT_OSS_PROVIDERS}; do
        case "${provider}" in
            openai) printf "  %-8s - Use OpenAI's official GPT-OSS repositories\\n" "${provider}" ;;
            unsloth) printf "  %-8s - Use Unsloth's optimized GPT-OSS GGUF repositories (recommended)\\n" "${provider}" ;;
        esac
    done
}

generate_config() {
    cat << EOF
# Universal HuggingFace GGUF Model Configuration
# Lines starting with # are comments

# Quantization level (Q2_K, Q3_K_S, Q3_K_M, Q3_K_L, Q4_K_S, Q4_K_M, Q5_K_S, Q5_K_M, Q6_K, Q8_0, F16, F32)
quants=${DEFAULT_QUANTS}

# HuggingFace source repository
hf_source=${DEFAULT_HF_SOURCE}

# Model name (leave empty to auto-detect from source)
model_name=${DEFAULT_MODEL}

# Model size (leave empty to auto-detect from source)
model_size=${DEFAULT_SIZE}

# Provider for GPT-OSS models (openai, unsloth)
provider=${DEFAULT_PROVIDER}

# Model basename for the created Ollama model
model_basename=${DEFAULT_MODEL_BASENAME}

# Python version to use with uv
python_version=${DEFAULT_PYTHON_VERSION}

# Repeat penalty parameter
repeat_penalty=${DEFAULT_REPEAT_PENALTY}

# Configuration file path (use default if not specified)
config_file=${DEFAULT_CONFIG_FILE}

# Log level (DEBUG, INFO, WARN, ERROR, QUIET)
log_level=INFO

# Enable verbose output (true/false)
verbose=false

# Perform dry run without executing commands (true/false)
dry_run=false

# Force overwrite existing files (true/false)
force=false
EOF
}

cleanup() {
    local exit_code=$?
    log "DEBUG" "Performing cleanup..."

    local temp_files=("${model_file}" "Modelfile" "$model_source")
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" && "${force}" != true ]]; then
            log "DEBUG" "Removing temporary file: ${file}"
            rm -f "${file}" 2>/dev/null || true
        fi
    done
    
    if [[ ${exit_code} -ne 0 ]]; then
        log "ERROR" "Script failed with exit code ${exit_code}"
    else
        log "DEBUG" "Script completed successfully"
    fi
}

main() {
    trap cleanup EXIT
    trap 'error_exit "Script interrupted"' INT TERM
    
    # First pass: only process config file option
    original_args=("$@")
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                config_file="${2:-}"
                [[ -z "${config_file}" ]] && error_exit "Config file path required"
                # Don't set cli_config_file_set here, let the main parsing do it
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    load_config
    
    # Reset arguments for main parsing
    set -- "${original_args[@]}"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quants)
                quants="${2:-}"
                [[ -z "${quants}" ]] && error_exit "Quantization level required"
                cli_quants_set="true"
                shift 2
                ;;
            -s|--source)
                hf_source="${2:-}"
                [[ -z "${hf_source}" ]] && error_exit "HuggingFace source required"
                cli_hf_source_set="true"
                shift 2
                ;;
            -m|--model)
                model_name="${2:-}"
                [[ -z "${model_name}" ]] && error_exit "Model name required"
                cli_model_name_set="true"
                shift 2
                ;;
            -z|--size)
                model_size="${2:-}"
                [[ -z "${model_size}" ]] && error_exit "Model size required"
                cli_model_size_set="true"
                shift 2
                ;;
            -P|--provider)
                provider="${2:-}"
                [[ -z "${provider}" ]] && error_exit "Provider required"
                cli_provider_set="true"
                shift 2
                ;;
            -b|--basename)
                model_basename="${2:-}"
                [[ -z "${model_basename}" ]] && error_exit "Model basename required"
                cli_model_basename_set="true"
                shift 2
                ;;
            -p|--python)
                python_version="${2:-}"
                [[ -z "${python_version}" ]] && error_exit "Python version required"
                cli_python_version_set="true"
                shift 2
                ;;
            -r|--repeat-penalty)
                repeat_penalty="${2:-}"
                [[ -z "${repeat_penalty}" ]] && error_exit "Repeat penalty required"
                cli_repeat_penalty_set="true"
                shift 2
                ;;
            -c|--config)
                config_file="${2:-}"
                [[ -z "${config_file}" ]] && error_exit "Config file path required"
                cli_config_file_set="true"
                shift 2
                ;;
            -l|--log-level)
                log_level="${2:-}"
                case "${log_level}" in
                    DEBUG|INFO|WARN|ERROR|QUIET) ;;
                    *) error_exit "Invalid log level. Use: DEBUG, INFO, WARN, ERROR, QUIET" ;;
                esac
                cli_log_level_set="true"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                cli_verbose_set="true"
                shift
                ;;
            -S|--silent)
                log_level="QUIET"
                cli_log_level_set="true"
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                cli_dry_run_set="true"
                shift
                ;;
            -f|--force)
                force=true
                cli_force_set="true"
                shift
                ;;
            --list-quants)
                list_quants
                exit 0
                ;;
            --list-providers)
                list_providers
                exit 0
                ;;
            --generate-config)
                generate_config
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                error_exit "Unexpected argument: $1"
                ;;
        esac
    done
    
    validate_quant "${quants}"
    
    validate_provider "${provider}"
    
    detect_model_info "${hf_source}"
    
    if [[ "${model_name}" == "gpt-oss" || "${model_name}" == "gpt_oss" ]]; then
        if [[ -z "${model_size}" ]]; then
            model_size="20b"
        fi
        
        resolved_source=$(resolve_gptoss_source "${provider}" "${model_size}")
        if [[ "${resolved_source}" != "${hf_source}" ]]; then
            log "INFO" "Using resolved GPT-OSS source: ${resolved_source} (provider: ${provider})"
            hf_source="${resolved_source}"
        fi
    elif [[ "${hf_source}" =~ (openai|unsloth)/gpt.?oss ]]; then
        if [[ -z "${model_name}" ]]; then
            model_name="gpt-oss"
        fi
        if [[ -z "${model_size}" ]]; then
            model_size="20b"
        fi
        
        resolved_source=$(resolve_gptoss_source "${provider}" "${model_size}")
        if [[ "${resolved_source}" != "${hf_source}" ]]; then
            log "INFO" "Detected GPT-OSS model, using resolved source: ${resolved_source} (provider: ${provider})"
            hf_source="${resolved_source}"
        fi
    fi
    
    check_dependencies
    check_required_files
    
    model_source=$(construct_gguf_filename "${model_name}" "${model_size}" "${quants}" "${hf_source}")
    
    if [[ -n "${model_size}" ]]; then
        model_target="${model_basename}-${model_size}-${quants}"
    else
        model_target="${model_basename}-${quants}"
    fi
    model_file="${model_target}.gguf"
    
    log "INFO" "Starting model creation with the following configuration:"
    log "INFO" "  Model: ${model_name}${model_size:+ (${model_size})}"
    log "INFO" "  Provider: ${provider}"
    log "INFO" "  Quantization: ${quants} ($(get_quant_description "${quants}"))"
    log "INFO" "  HuggingFace Source: ${hf_source}"
    log "INFO" "  GGUF file: ${model_source}"
    log "INFO" "  Model basename: ${model_basename}"
    log "INFO" "  Model target: ${model_target}"
    log "INFO" "  Python version: ${python_version}"
    log "INFO" "  Repeat penalty: ${repeat_penalty}"
    log "INFO" "  Dry run: ${dry_run}"
    
    if [[ "${dry_run}" == true ]]; then
        log "INFO" "DRY RUN - Commands that would be executed:"
        echo "export HF_HUB_ENABLE_HF_TRANSFER=1"
        echo "uv tool install 'huggingface_hub[cli]'"
        echo "hf download ${hf_source} --local-dir . --include '${model_source}'"
        echo "cp Modelfile.base Modelfile"
        echo "sed -i '' 's|^FROM.*|FROM ${model_source}|' Modelfile"
        echo "cat SYSTEM.md >> Modelfile"
        echo "ollama create ${model_target} -f Modelfile"
        echo "rm ${model_file} Modelfile"
        exit 0
    fi
    
    export HF_HUB_ENABLE_HF_TRANSFER=1
    
    log "INFO" "Installing HuggingFace CLI..."
    if ! uv tool install "huggingface_hub[cli]"; then
        error_exit "Failed to install HuggingFace CLI"
    fi
    
    log "INFO" "Downloading model: ${model_source}"
    
    download_patterns=("${model_source}")
    
    if [[ "${model_name}" != "gpt-oss" && "${model_name}" != "gpt_oss" ]]; then
        alt_filename="${model_name}.${quants}.gguf"
        if [[ "${alt_filename}" != "${model_source}" ]]; then
            download_patterns+=("${alt_filename}")
        fi
        
        if [[ -n "${model_size}" ]]; then
            alt_filename2="${model_name}-${model_size}.${quants}.gguf"
            if [[ "${alt_filename2}" != "${model_source}" && "${alt_filename2}" != "${alt_filename}" ]]; then
                download_patterns+=("${alt_filename2}")
            fi
        fi
    fi
    
    downloaded=false
    for pattern in "${download_patterns[@]}"; do
        log "DEBUG" "Trying to download: ${pattern}"
        if hf download "${hf_source}" --local-dir . --include "${pattern}" 2>/dev/null; then
            if [[ -f "${pattern}" ]]; then
                if [[ "${pattern}" != "${model_source}" ]]; then
                    log "INFO" "Downloaded ${pattern}, renaming to ${model_source}"
                    mv "${pattern}" "${model_source}"
                fi
                downloaded=true
                break
            fi
        fi
    done
    
    if [[ "${downloaded}" != true ]]; then
        log "WARN" "Failed to download specific GGUF file, trying to list available files..."
        if ! hf download "${hf_source}" --local-dir . --include "*.gguf"; then
            error_exit "Failed to download any GGUF files from ${hf_source}"
        fi
        
        available_files=$(find . -name "*.gguf" -maxdepth 1 2>/dev/null)
        if [[ -z "${available_files}" ]]; then
            error_exit "No GGUF files found after download"
        fi
        
        log "INFO" "Available GGUF files:"
        echo "${available_files}"
        error_exit "Could not find expected GGUF file: ${model_source}. Please check the filename pattern."
    fi
    
    log "INFO" "Creating Modelfile..."
    if ! cp Modelfile.base Modelfile; then
        error_exit "Failed to copy Modelfile.base"
    fi
    
    if ! sed -i '' "s|^FROM.*|FROM ${model_source}|" Modelfile; then
        error_exit "Failed to update Modelfile FROM directive"
    fi
    
    cat << EOF >> Modelfile
PARAMETER repeat_penalty ${repeat_penalty}
SYSTEM """
EOF
    
    if ! cat SYSTEM.md >> Modelfile; then
        error_exit "Failed to append SYSTEM.md to Modelfile"
    fi
    
    echo -n '"""' >> Modelfile
    
    log "INFO" "Creating Ollama model: ${model_target}"
    if ! ollama create "${model_target}" -f Modelfile; then
        error_exit "Failed to create Ollama model"
    fi
    
    log "INFO" "Model creation completed successfully"
    log "INFO" "Created model: ${model_target}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi