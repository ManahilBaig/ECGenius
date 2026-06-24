"""
ML Service for ECG Classification using trained Random Forest model.
"""

import os
import numpy as np
from typing import List, Dict, Any

try:
    import joblib
except ImportError:
    joblib = None

class MLService:
    def __init__(self):
        self.model = None
        self.scaler = None
        self.model_loaded = False
        self._load_model()

    def _load_model(self):
        """Load the trained model and scaler from files."""
        try:
            model_path = os.path.join(os.path.dirname(__file__), '../../../cardiac_ml/best_cardiac_model.pkl')
            scaler_path = os.path.join(os.path.dirname(__file__), '../../../cardiac_ml/scaler.pkl')

            if joblib is None:
                print("joblib not installed; ML model loading skipped")
            elif os.path.exists(model_path) and os.path.exists(scaler_path):
                self.model = joblib.load(model_path)
                self.scaler = joblib.load(scaler_path)
                self.model_loaded = True
                print("ML model and scaler loaded successfully")
            else:
                print(f"Model files not found: {model_path}, {scaler_path}")
        except Exception as e:
            print(f"Error loading ML model: {e}")

    def predict_ecg_class(self, features: Dict[str, Any]) -> Dict[str, Any]:
        """
        Predict ECG class from extracted features.

        Args:
            features: Dictionary containing ECG features

        Returns:
            Dictionary with prediction results
        """
        if not self.model_loaded:
            return {
                "prediction": "unknown",
                "confidence": 0.0,
                "error": "ML model not loaded"
            }

        try:
            # Convert features to DataFrame (similar to training data)
            feature_names = [
                'hbpermin', 'Pseg', 'PQseg', 'QRSseg', 'QRseg', 'QTseg', 'RSseg', 'STseg', 'Tseg',
                'PTseg', 'ECGseg', 'QRtoQSdur', 'RStoQSdur', 'RRmean', 'PPmean', 'PQdis',
                'PonQdis', 'PRdis', 'PonRdis', 'PSdis', 'PonSdis', 'PTdis', 'PonTdis', 'PToffdis',
                'QRdis', 'QSdis', 'QTdis', 'QToffdis', 'RSdis', 'RTdis', 'RToffdis', 'STdis',
                'SToffdis', 'PonToffdis', 'PonPQang', 'PQRang', 'QRSang', 'RSTang', 'STToffang',
                'RRTot', 'NNTot', 'SDRR', 'IBIM', 'IBISD', 'SDSD', 'RMSSD', 'QRSarea', 'QRSperi',
                'PQslope', 'QRslope', 'RSslope', 'STslope', 'NN50', 'pNN50'
            ]

            # Create feature array
            feature_values = []
            for name in feature_names:
                value = features.get(name, 0.0)
                if value is None:
                    value = 0.0
                try:
                    if np.isnan(value):
                        value = 0.0
                except TypeError:
                    pass
                feature_values.append(float(value))

            # Convert to numpy array and reshape
            X = np.array(feature_values).reshape(1, -1)

            # Scale features
            X_scaled = self.scaler.transform(X)

            # Make prediction
            prediction_encoded = self.model.predict(X_scaled)[0]
            prediction_proba = self.model.predict_proba(X_scaled)[0]

            # Map encoded prediction back to class name
            class_mapping = {0: 'AFF', 1: 'ARR', 2: 'CHF', 3: 'NSR'}
            predicted_class = class_mapping.get(prediction_encoded, 'unknown')
            confidence = float(prediction_proba[prediction_encoded])

            return {
                "prediction": predicted_class,
                "confidence": confidence,
                "probabilities": {
                    "AFF": float(prediction_proba[0]),
                    "ARR": float(prediction_proba[1]),
                    "CHF": float(prediction_proba[2]),
                    "NSR": float(prediction_proba[3])
                }
            }

        except Exception as e:
            return {
                "prediction": "error",
                "confidence": 0.0,
                "error": str(e)
            }

# Global ML service instance
ml_service = MLService()
