# Pix Universal GGUF Model Creation

# Default recipe - show help
default:
    just --list

# Create default GPT-OSS model with recommended settings
create-default:
    ./dl-gguf.sh

# Download and create with specific quantization (Q4_K_M = balanced quality)
create-q4:
    ./dl-gguf.sh --quants Q4_K_M

# GPT-OSS Provider Examples
# ========================

# Use OpenAI's official GPT-OSS repository
create-openai:
    ./dl-gguf.sh --provider openai --size 20b --quants Q4_K_M

# Use Unsloth's optimized GPT-OSS repository (recommended for performance)
create-unsloth:
    ./dl-gguf.sh --provider unsloth --size 20b --quants Q5_K_S

# Create with custom basename and repeat penalty (affects text generation behavior)
create-tuned penalty:
    ./dl-gguf.sh --repeat-penalty {{penalty}}

# Use specific Python version with uv (useful for compatibility)
create-python-version version:
    ./dl-gguf.sh --python {{version}}

# Generate sample configuration file for persistent settings
generate-config:
    ./dl-gguf.sh --generate-config > .dl-gguf-config

# Use custom configuration file location
create-with-config config_file:
    ./dl-gguf.sh --config {{config_file}}

# List all available quantization levels with descriptions
list-quants:
    ./dl-gguf.sh --list-quants

# List available providers for GPT-OSS models
list-providers:
    ./dl-gguf.sh --list-providers

# Perform dry run to see what commands would be executed (no actual download)
dry-run:
    ./dl-gguf.sh --dry-run --verbose

# Create multiple models with different quantizations (run separately)
create-multi-quant:
    ./dl-gguf.sh --quants Q4_K_M --basename Pix-Q4
    ./dl-gguf.sh --quants Q6_K --basename Pix-Q6

# Clean up temporary files (manual cleanup if script fails)
clean:
    rm -f *.gguf Modelfile *.log

# Show current configuration (if config file exists)
show-config:
    #!/bin/bash
    if [ -f .dl-gguf-config ]; then cat .dl-gguf-config; else echo "No config file found. Run 'just generate-config' first."; fi

# Validate dependencies are installed
check-deps:
    #!/bin/bash
    echo "Checking dependencies..."
    command -v uv >/dev/null || echo "❌ uv not found"
    command -v ollama >/dev/null || echo "❌ ollama not found" 
    command -v wget >/dev/null || echo "❌ wget not found"
    echo "✅ Dependency check complete"

# Complete setup for first-time users
setup-first-time:
    just generate-config
    just check-deps
    just show-config
