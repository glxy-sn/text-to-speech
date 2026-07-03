from transformers import AutoTokenizer
tokenizer = AutoTokenizer.from_pretrained("mlx-community/Fun-CosyVoice3-0.5B-2512-8bit")
print("Special tokens:", tokenizer.all_special_tokens)
print("Language tags?", [t for t in tokenizer.all_special_tokens if '|' in t])
