import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.impute import SimpleImputer
from sklearn.ensemble import RandomForestClassifier
from sklearn.svm import SVC
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import seaborn as sns
import os
from imblearn.over_sampling import SMOTE

# Load the dataset
def load_data(data_path):
    """Load the cardiac dataset"""
    if os.path.exists(data_path):
        df = pd.read_csv(data_path)
        print(f"Dataset loaded successfully. Shape: {df.shape}")
        return df
    else:
        print(f"Dataset not found at {data_path}")
        return None

# Data preprocessing
def preprocess_data(df):
    """Preprocess the data: handle missing values, encode categorical variables"""
    print("Preprocessing data...")

    # Check for missing values
    print(f"Missing values:\n{df.isnull().sum()}")

    # Encode categorical target variable if needed
    if df['ECG_signal'].dtype == 'object':
        le = LabelEncoder()
        df['ECG_signal'] = le.fit_transform(df['ECG_signal'])
        print(f"Encoded target classes: {le.classes_}")

    # Separate features and target
    X = df.drop('ECG_signal', axis=1)
    y = df['ECG_signal']

    # Drop ID column if present
    if 'RECORD' in X.columns:
        X = X.drop('RECORD', axis=1)

    # Impute missing values in features
    imputer = SimpleImputer(strategy='mean')
    X = pd.DataFrame(imputer.fit_transform(X), columns=X.columns)

    return X, y

# Feature scaling
def scale_features(X_train, X_test):
    """Scale the features using StandardScaler"""
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    return X_train_scaled, X_test_scaled, scaler

# Handle class imbalance
def handle_imbalance(X, y):
    """Handle class imbalance using SMOTE"""
    smote = SMOTE(random_state=42)
    X_resampled, y_resampled = smote.fit_resample(X, y)
    print(f"After SMOTE: {X_resampled.shape}, {y_resampled.shape}")
    return X_resampled, y_resampled

# Train and evaluate models
def train_evaluate_models(X_train, X_test, y_train, y_test):
    """Train and evaluate different ML models"""
    models = {
        'Random Forest': RandomForestClassifier(n_estimators=100, random_state=42),
        'SVM': SVC(kernel='rbf', random_state=42),
        'Logistic Regression': LogisticRegression(random_state=42, max_iter=1000)
    }

    results = {}

    for name, model in models.items():
        print(f"\nTraining {name}...")

        # Train the model
        model.fit(X_train, y_train)

        # Make predictions
        y_pred = model.predict(X_test)

        # Evaluate
        accuracy = accuracy_score(y_test, y_pred)
        report = classification_report(y_test, y_pred)

        results[name] = {
            'model': model,
            'accuracy': accuracy,
            'report': report,
            'predictions': y_pred
        }

        print(f"{name} Accuracy: {accuracy:.4f}")
        print(f"Classification Report:\n{report}")

    return results

# Plot confusion matrix
def plot_confusion_matrix(y_test, y_pred, title):
    """Plot confusion matrix"""
    cm = confusion_matrix(y_test, y_pred)
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues')
    plt.title(f'Confusion Matrix - {title}')
    plt.ylabel('True Label')
    plt.xlabel('Predicted Label')
    plt.savefig(f'confusion_matrix_{title.replace(" ", "_")}.png')
    plt.close()  # Close the figure to avoid display issues
    print(f"Confusion matrix saved as confusion_matrix_{title.replace(' ', '_')}.png")

# Main pipeline
def main():
    # Dataset path (adjust based on actual dataset structure)
    data_path = 'ECGCvdata.csv'  # Adjust this path

    # Load data
    df = load_data(data_path)
    if df is None:
        return

    # Preprocess data
    X, y = preprocess_data(df)

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    # Handle class imbalance
    X_train_resampled, y_train_resampled = handle_imbalance(X_train, y_train)

    # Scale features
    X_train_scaled, X_test_scaled, scaler = scale_features(X_train_resampled, X_test)

    # Train and evaluate models
    results = train_evaluate_models(X_train_scaled, X_test_scaled, y_train_resampled, y_test)

    # Plot confusion matrices for best models
    best_model = max(results.items(), key=lambda x: x[1]['accuracy'])
    print(f"\nBest Model: {best_model[0]} with accuracy {best_model[1]['accuracy']:.4f}")

    # Plot confusion matrix for best model
    plot_confusion_matrix(y_test, best_model[1]['predictions'], best_model[0])

    # Save the best model
    import joblib
    joblib.dump(best_model[1]['model'], 'best_cardiac_model.pkl')
    joblib.dump(scaler, 'scaler.pkl')
    print("Model and scaler saved successfully!")

if __name__ == "__main__":
    main()
