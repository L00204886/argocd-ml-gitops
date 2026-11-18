"""Observable Flask ML Microservice for ArgoCD Multi-Environment GitOps Demo."""

from html import escape
import os
from pathlib import Path
import pickle
from flask import Flask, jsonify, request

app = Flask(__name__)

# TIP: Change GREETING below, commit, and `git push` to watch GitHub Actions
# build a new multi-arch Docker Hub image and see ArgoCD auto-sync `testing`
# while `production` turns OutOfSync waiting for manual approval!
GREETING = "Welcome Everyone"

MODEL_PATH = Path(__file__).resolve().parent / "model.pkl"
with MODEL_PATH.open("rb") as _fh:
    MODEL = pickle.load(_fh)


def runtime_metadata() -> dict:
    return {
        "environment": os.getenv("APP_ENV", "local"),
        "version": os.getenv("APP_VERSION", "dev"),
        "pod": os.getenv("POD_NAME", "local-process"),
        "namespace": os.getenv("POD_NAMESPACE", "default"),
        "node": os.getenv("NODE_NAME", "macos-host"),
    }


def predict_salary(experience: float) -> float:
    return round(MODEL["intercept"] + MODEL["slope"] * experience, 2)


@app.get("/healthz")
def healthz():
    return jsonify({"status": "ok", "model_loaded": bool(MODEL)}), 200


@app.get("/predict")
def predict():
    raw = request.args.get("experience", "5.5")
    try:
        experience = float(raw)
    except ValueError:
        return jsonify({"error": f"Invalid experience value: {raw!r}. Pass a number like ?experience=5.5"}), 400

    if experience < 0 or experience > 60:
        return jsonify({"error": "experience must be between 0 and 60 years"}), 400

    meta = runtime_metadata()
    return jsonify(
        {
            "greeting": GREETING,
            "experience_years": experience,
            "predicted_salary": predict_salary(experience),
            "currency": "EUR",
            "model": MODEL,
            **meta,
        }
    )


@app.get("/")
def index():
    meta = runtime_metadata()
    env_name = meta["environment"]
    badge_bg = "#059669" if env_name == "production" else "#d97706" if env_name == "testing" else "#4f46e5"
    sample_exp = 5.5
    sample_salary = predict_salary(sample_exp)

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{escape(GREETING)} — {escape(env_name.upper())}</title>
  <style>
    :root {{ color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    body {{ max-width: 720px; margin: 2.5rem auto; padding: 0 1.25rem; line-height: 1.5; }}
    .card {{ border: 1px solid rgba(128,128,128,0.3); border-radius: 12px; padding: 1.5rem; margin-bottom: 1.25rem; }}
    .badge {{ display: inline-block; background: {badge_bg}; color: #fff; font-weight: 700;
              padding: 0.25rem 0.75rem; border-radius: 999px; font-size: 0.85rem; text-transform: uppercase; }}
    dl {{ display: grid; grid-template-columns: 150px 1fr; gap: 0.5rem 1rem; margin: 1rem 0 0; }}
    dt {{ font-weight: 600; opacity: 0.75; }}
    dd {{ margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92rem; }}
    form {{ display: flex; gap: 0.75rem; align-items: center; flex-wrap: wrap; margin-top: 0.75rem; }}
    input {{ padding: 0.5rem 0.75rem; border-radius: 8px; border: 1px solid rgba(128,128,128,0.4); width: 120px; font-size: 1rem; }}
    button {{ padding: 0.55rem 1rem; border-radius: 8px; border: none; background: #2563eb; color: #fff; font-weight: 600; cursor: pointer; }}
    #result {{ margin-top: 1rem; font-weight: 600; font-size: 1.05rem; }}
  </style>
</head>
<body>
  <div class="card">
    <div style="display:flex; justify-content:space-between; align-items:center; gap:1rem;">
      <h1 style="margin:0; font-size:1.6rem;">{escape(GREETING)}</h1>
      <span class="badge">{escape(env_name)}</span>
    </div>
    <p style="margin:0.5rem 0 0; opacity:0.8;">ArgoCD GitOps ML Service running on Kubernetes (kind)</p>
    <dl>
      <dt>Namespace</dt><dd>{escape(meta["namespace"])}</dd>
      <dt>Pod Name</dt><dd>{escape(meta["pod"])}</dd>
      <dt>Worker Node</dt><dd>{escape(meta["node"])}</dd>
      <dt>Image Version</dt><dd>{escape(meta["version"])}</dd>
      <dt>Model R&sup2;</dt><dd>{MODEL["r_squared"]} ({MODEL["samples"]} training samples)</dd>
    </dl>
  </div>

  <div class="card">
    <h2 style="margin-top:0; font-size:1.2rem;">Salary Prediction Model</h2>
    <p style="margin:0; opacity:0.85;">
      Direct API endpoint: <a href="/predict?experience={sample_exp}"><code>/predict?experience={sample_exp}</code></a>
      (&rarr; &euro;{sample_salary:,.2f})
    </p>
    <form id="pred-form" action="/predict" method="get">
      <label for="exp">Years of Experience:</label>
      <input id="exp" name="experience" type="number" step="0.1" min="0" max="60" value="{sample_exp}" required />
      <button type="submit">Predict Salary</button>
    </form>
    <div id="result"></div>
  </div>

  <script>
    document.getElementById("pred-form").addEventListener("submit", async (e) => {{
      e.preventDefault();
      const exp = document.getElementById("exp").value;
      const res = await fetch(`/predict?experience=${{encodeURIComponent(exp)}}`);
      const data = await res.json();
      const el = document.getElementById("result");
      if (data.error) {{
        el.textContent = `Error: ${{data.error}}`;
      }} else {{
        el.textContent = `Predicted Salary for ${{data.experience_years}} yrs: EUR ${{data.predicted_salary.toLocaleString()}} (served by ${{data.pod}} on ${{data.node}})`;
      }}
    }});
  </script>
</body>
</html>"""
    return html, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
