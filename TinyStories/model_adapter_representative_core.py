from __future__ import annotations

"""Reduced GPT-Neo core derived from the TinyStories-1M config for fast iteration."""

import os

import torch
from transformers import AutoConfig, AutoModelForCausalLM


EXPORT_STRICT = False

DEFAULT_VOCAB_SIZE = 32
DEFAULT_NUM_LAYERS = 2
DEFAULT_MAX_POSITION_EMBEDDINGS = 4
DEFAULT_WINDOW_SIZE = 2
DEFAULT_HIDDEN_SIZE = 2
DEFAULT_NUM_HEADS = 1


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    return int(value)


def attention_types_for_layers(num_layers: int) -> list[list[object]]:
    pattern = ["global", "local"]
    full_repeats, remainder = divmod(num_layers, len(pattern))
    attention_types: list[list[object]] = []
    if full_repeats:
        attention_types.append([pattern, full_repeats])
    if remainder:
        attention_types.append([pattern[:remainder], 1])
    return attention_types


def build_model(model_path: str | None) -> torch.nn.Module:
    if model_path is None:
        raise RuntimeError("TinyStories adapter requires --model-path")

    config = AutoConfig.from_pretrained(model_path, local_files_only=True)
    config.vocab_size = env_int("TINYSTORIES_CORE_VOCAB_SIZE", DEFAULT_VOCAB_SIZE)
    config.num_layers = env_int("TINYSTORIES_CORE_NUM_LAYERS", DEFAULT_NUM_LAYERS)
    config.max_position_embeddings = env_int(
        "TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS",
        DEFAULT_MAX_POSITION_EMBEDDINGS,
    )
    config.window_size = env_int("TINYSTORIES_CORE_WINDOW_SIZE", DEFAULT_WINDOW_SIZE)
    config.hidden_size = env_int("TINYSTORIES_CORE_HIDDEN_SIZE", DEFAULT_HIDDEN_SIZE)
    config.num_heads = env_int("TINYSTORIES_CORE_NUM_HEADS", DEFAULT_NUM_HEADS)
    config.attention_types = attention_types_for_layers(config.num_layers)
    config.attention_layers = config.expand_attention_types_params(config.attention_types)
    config.use_cache = False
    config.bos_token_id = config.vocab_size - 1
    config.eos_token_id = config.vocab_size - 1

    torch.manual_seed(0)
    return AutoModelForCausalLM.from_config(config).eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.zeros((1, 1), dtype=torch.long),)
