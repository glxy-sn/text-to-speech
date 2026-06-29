from transformers import Wav2Vec2Processor
import json

processor = Wav2Vec2Processor.from_pretrained("jonatasgrosman/wav2vec2-large-xlsr-53-english")
vocab = processor.tokenizer.get_vocab()
sorted_vocab = [k for k, v in sorted(vocab.items(), key=lambda x: x[1])]
print(json.dumps(sorted_vocab))
