"""Deterministic build-time training script for the Salary Prediction ML model.

Runs during `docker build` to serialize `model.pkl` directly into the image,
preventing runtime FileNotFoundError crashes on Kubernetes worker nodes.
"""

from pathlib import Path
import pickle
import statistics

# Classic YearsExperience -> Annual Salary dataset (in EUR)
TRAINING_DATA = [
    (1.1, 39343.0),
    (1.5, 37731.0),
    (2.0, 43525.0),
    (2.9, 56642.0),
    (3.2, 60150.0),
    (4.0, 56957.0),
    (4.5, 61111.0),
    (5.1, 66029.0),
    (5.9, 81363.0),
    (6.8, 91738.0),
    (7.9, 101302.0),
    (8.7, 109431.0),
    (9.5, 116969.0),
    (10.3, 121872.0),
]


def train_and_save(output_path: Path) -> None:
    xs = [row[0] for row in TRAINING_DATA]
    ys = [row[1] for row in TRAINING_DATA]

    slope, intercept = statistics.linear_regression(xs, ys)
    r_corr = statistics.correlation(xs, ys)

    artefact = {
        "model_type": "OrdinaryLeastSquaresLinearRegression",
        "slope": round(slope, 4),
        "intercept": round(intercept, 4),
        "r_squared": round(r_corr**2, 4),
        "samples": len(TRAINING_DATA),
    }

    with output_path.open("wb") as fh:
        pickle.dump(artefact, fh)

    sample_pred = intercept + slope * 5.5
    print(
        f"Saved {output_path} | slope={artefact['slope']}, "
        f"intercept={artefact['intercept']}, R^2={artefact['r_squared']} "
        f"| 5.5 yrs -> EUR {sample_pred:,.2f}"
    )


if __name__ == "__main__":
    train_and_save(Path(__file__).resolve().parent / "model.pkl")
