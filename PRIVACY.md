# Privacy Policy & Terms of Use

**Last updated: May 2026**

---

## Privacy Policy

### Overview

This app is designed with privacy as a core principle. All AI processing happens entirely on your device. We do not collect, store, or transmit any personal data.

### Data Collection

**We collect no data.** Specifically:

- No analytics or telemetry
- No crash reporting sent to us
- No user accounts or registration
- No cookies or tracking
- No advertising or ad identifiers
- No data shared with third parties

### On-Device Data

The following data is stored **only on your device** and never leaves it:

- **Chat history** - Stored in app sandbox. Only accessible by this app.
- **Financial transactions** - Extracted from statements you upload. Stored locally in app sandbox.
- **Health data** - Queried live from Apple HealthKit with your permission. Not cached or stored by this app.
- **AI models** - Downloaded model files stored in the app's Documents directory.
- **Settings and preferences** - Stored locally on device.

### Apple HealthKit

This app requests read-only access to HealthKit data including steps, distance, sleep, heart rate, exercise, and active calories. This data is:
- Queried directly from HealthKit on your device
- Used solely to provide AI-powered health insights
- Never transmitted, uploaded, or shared
- Never stored outside of HealthKit

You can revoke HealthKit access at any time in iOS Settings > Privacy & Security > Health.

### Ollama (Optional)

If you choose to connect to Ollama, your prompts and AI responses are sent over your **local WiFi network** to a server you control. This data:
- Is sent only to the IP address you configure
- Travels over your local network (not the internet)
- Is not encrypted in transit (HTTP)
- Is never sent to any third-party server

Ollama is entirely optional. The app functions fully without it.

### Financial Statements

When you upload bank or credit card statements:
- Text is extracted on-device using Apple's PDFKit and Vision OCR
- Extracted data is processed by the on-device AI model
- Parsed transactions are stored locally in app sandbox
- Original PDF/image files are not retained after extraction
- No financial data is transmitted anywhere

### Children's Privacy

This app does not knowingly collect information from children under 13.

---

## Terms of Use

### Acceptance

By using this app, you agree to these terms. If you do not agree, do not use the app.

### Nature of the Service

This app provides AI-generated responses using language models running on your device. The app is provided "as is" without warranties of any kind.

### No Professional Advice

**This app does not provide medical, financial, legal, or professional advice.** AI-generated content about health data or financial transactions is for informational and personal tracking purposes only. You should:
- Not rely on AI responses for medical decisions. Always consult a qualified healthcare provider.
- Not rely on AI responses for financial decisions. Always consult a qualified financial advisor.
- Not use AI responses as a substitute for professional judgment in any field.

### Accuracy

AI models may produce inaccurate, incomplete, or misleading responses. We make no guarantees about the accuracy, reliability, or completeness of any AI-generated content. You are solely responsible for evaluating and acting on any information provided.

### Your Data

You are responsible for the data you input into this app, including uploaded financial statements and health data access. All data remains on your device under your control.

### Third-Party Models

AI models available through this app are created by third parties (Hugging Face community, Google, Meta, Alibaba, Mistral AI, etc.) and are subject to their respective licenses. We do not create, train, or control these models.

### Limitation of Liability

To the maximum extent permitted by law, the developers of this app shall not be liable for any direct, indirect, incidental, special, or consequential damages arising from your use of the app, including but not limited to:
- Decisions made based on AI-generated health or financial insights
- Inaccurate extraction or categorization of financial data
- Loss of data stored on your device
- Any damages resulting from AI model outputs

### Indemnification

You agree to indemnify and hold harmless the developers from any claims, damages, or expenses arising from your use of the app.

### Open Source

This app is open source under the GPL-3.0 license. The source code is available at [github.com/leonickson1/localLLM](https://github.com/leonickson1/localLLM).

### Changes

We may update these terms. Continued use of the app after changes constitutes acceptance of the updated terms.

---

## Contact

For questions, open an issue at [github.com/leonickson1/localLLM](https://github.com/leonickson1/localLLM/issues).
