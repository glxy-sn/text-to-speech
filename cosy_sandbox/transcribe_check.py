import mlx_whisper

result = mlx_whisper.transcribe("test_output_000.wav", path_or_hf_repo="mlx-community/whisper-large-v3-turbo")
print("TRANSCRIPTION:")
print(result["text"])
