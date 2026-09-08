# Third-party notices

Murmur uses these projects; their licenses remain separate from Murmur's source license:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) for local speech recognition.
- [MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) for local text generation.
- [Swift Hugging Face](https://github.com/huggingface/swift-huggingface) and [Swift Transformers](https://github.com/huggingface/swift-transformers) for model downloads and tokenization.

The release script includes license and notice files from resolved dependencies, including transitive dependencies, in `Murmur.app/Contents/Resources/ThirdPartyLicenses/`.

## Downloaded models

Speech recognition uses NVIDIA's **Parakeet TDT 0.6B v2**, converted to CoreML by FluidInference. The [CoreML model card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml) identifies its license as [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Murmur uses these converted weights without further modification. Attribution: NVIDIA (original model), FluidInference (CoreML conversion).

AI polishing uses [mlx-community/Qwen3.5-2B-4bit](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit), an MLX quantization of Qwen3.5-2B. See that repository's model card and license for the model's terms and upstream attribution. Model weights are downloaded on first use rather than distributed inside Murmur's release ZIP.
