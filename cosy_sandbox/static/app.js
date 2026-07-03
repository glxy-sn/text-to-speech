document.addEventListener("DOMContentLoaded", () => {
    const form = document.getElementById("tts-form");
    const select = document.getElementById("reference_voice");
    const refAudioPlayer = document.getElementById("ref-audio-player");

    const generateBtn = document.getElementById("generate-btn");
    const btnText = form.querySelector(".btn-text");
    const btnLoader = document.getElementById("btn-loader");

    const resultSection = document.getElementById("result-section");
    const outputAudio = document.getElementById("output-audio");
    const downloadLink = document.getElementById("download-link");
    const errorToast = document.getElementById("error-message");

    // Pace badge elements
    const paceBadge = document.getElementById("pace-badge");
    const paceWpmText = document.getElementById("pace-wpm-text");
    const paceNormText = document.getElementById("pace-norm-text");
    const paceFinalText = document.getElementById("pace-final-text");

    // Pace slider live update
    const speedSlider = document.getElementById("speed-slider");
    const speedDisplay = document.getElementById("speed-display");

    function updateSliderFill(slider) {
        const min = parseFloat(slider.min);
        const max = parseFloat(slider.max);
        const val = parseFloat(slider.value);
        const pct = ((val - min) / (max - min) * 100).toFixed(2) + "%";
        slider.style.setProperty("--range-pct", pct);
    }

    speedSlider.addEventListener("input", () => {
        const val = parseFloat(speedSlider.value).toFixed(2);
        speedDisplay.textContent = val;
        updateSliderFill(speedSlider);
        // Visual feedback: color the badge warm if > 1, cool if < 1
        const badge = speedDisplay.closest(".slider-value-badge");
        if (badge) {
            badge.classList.toggle("fast", parseFloat(val) > 1.05);
            badge.classList.toggle("slow", parseFloat(val) < 0.95);
            badge.classList.toggle("neutral", parseFloat(val) >= 0.95 && parseFloat(val) <= 1.05);
        }
    });
    // Initialise neutral class and fill
    speedDisplay.closest(".slider-value-badge").classList.add("neutral");
    updateSliderFill(speedSlider);


    // Fetch available voices
    fetch("/voices_list")
        .then(res => res.json())
        .then(data => {
            select.innerHTML = '<option value="" disabled selected>Select a voice...</option>';
            data.voices.forEach(voice => {
                const option = document.createElement("option");
                option.value = voice;
                option.textContent = voice.replace('_short.wav', '').replace(/_/g, ' ');
                select.appendChild(option);
            });
        })
        .catch(err => {
            console.error("Failed to load voices:", err);
            select.innerHTML = '<option value="" disabled>Error loading voices</option>';
        });

    // Update preview audio when voice selected
    select.addEventListener("change", (e) => {
        const filename = e.target.value;
        if (filename) {
            refAudioPlayer.src = `/voices/${filename}`;
        }
    });

    // Form Submit
    form.addEventListener("submit", async (e) => {
        e.preventDefault();

        // Reset UI
        errorToast.style.display = "none";
        resultSection.style.display = "none";
        paceBadge.style.display = "none";
        outputAudio.src = "";

        // UI Loading state
        btnText.textContent = "Generating...";
        btnLoader.style.display = "block";
        generateBtn.disabled = true;

        const refLengthVal = document.querySelector('input[name="ref_length"]:checked')?.value || "short";
        const speedVal = speedSlider.value;

        const formData = new FormData();
        formData.append("text", document.getElementById("text").value);
        formData.append("reference_voice", select.value);
        formData.append("target_language", document.getElementById("target_language").value);
        formData.append("speed", speedVal);
        formData.append("ref_length", refLengthVal);

        try {
            const response = await fetch("/generate", {
                method: "POST",
                body: formData
            });

            if (!response.ok) {
                const errData = await response.json();
                throw new Error(errData.detail || "Failed to generate audio");
            }

            // Read pace metadata from custom headers
            const detectedWpm = response.headers.get("X-Detected-WPM");
            const normFactor  = response.headers.get("X-Norm-Factor");
            const finalSpeed  = response.headers.get("X-Final-Speed");

            // Handle audio blob response
            const blob = await response.blob();
            const audioUrl = URL.createObjectURL(blob);

            outputAudio.src = audioUrl;
            downloadLink.href = audioUrl;

            // Populate and show pace badge
            if (detectedWpm && normFactor && finalSpeed) {
                paceWpmText.textContent  = `Ref pace: ${detectedWpm} WPM`;
                paceNormText.textContent = `Norm: ${normFactor}×`;
                paceFinalText.textContent = `Final: ${finalSpeed}×`;
                paceBadge.style.display = "flex";
            }

            resultSection.style.display = "block";
            // Auto play
            outputAudio.play().catch(e => console.log("Autoplay prevented:", e));

        } catch (error) {
            errorToast.textContent = error.message;
            errorToast.style.display = "block";
        } finally {
            // Restore UI
            btnText.textContent = "Generate Speech";
            btnLoader.style.display = "none";
            generateBtn.disabled = false;
        }
    });
});
