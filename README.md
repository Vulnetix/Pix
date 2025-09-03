# Pix by Vulnetix

Pix is a secure coding assistant delivered as a fine‑tuned GGUF model for your favourite open‑weight models.
It ships with built‑in tool support for use with CLI coding agents.

## Usage

You can also extend the tool set by adding custom scripts in the `justfile` or `dl-gguf.sh`.

## Model Card

| Attribute | Value |
|-----------|-------|
| Model type | GGUF (Quantized) |
| Base model | OpenWeight (e.g. Llama‑2) |
| Size | 1.2 GB |
| Quantization | 4‑bit |
| License | Apache‑2.0 |

### Features

- Tool support – the CLI can invoke external tools such as linters, formatters, test runners, and shell commands.
- Fine‑tuned – the model is adapted to the domain of coding assistance.
- Secure coding – the model is trained to suggest safe, production‑ready code.
