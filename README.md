---
license: apache-2.0
base_model: llama-2
model-index:
- name: Pix by Vulnetix
  results: []
tags:
- code-generation
- coding-assistant
- gguf
- quantized
- secure-coding
library_name: transformers
pipeline_tag: text-generation
repo: https://github.com/Vulnetix/Pix
---

# Pix by Vulnetix

**Repository:** [https://github.com/Vulnetix/Pix](https://github.com/Vulnetix/Pix)

Pix is a secure coding assistant delivered as a fine‑tuned GGUF model for your favourite open‑weight models.
It ships with built‑in tool support for use with CLI coding agents.

| Attribute | Value |
|-----------|-------|
| Model type | GGUF (Quantized) |
| Base model | OpenWeight (GPT-OSS) |
| License | Apache‑2.0 inherent from base model |

## Usage

You can also extend the tool set by adding custom scripts in the `justfile` or run `dl-gguf.sh` directly.

### Features

- Tool support – the CLI can invoke external tools such as linters, formatters, test runners, and shell commands.
- Fine‑tuned – the model is adapted to the domain of coding assistance.
- Secure coding – the model is trained to suggest safe, production‑ready code.
