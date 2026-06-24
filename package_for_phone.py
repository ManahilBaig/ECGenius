import os
import zipfile

def package_backend():
    print("Packaging backend for phone transfer...")
    
    # Current directory (App root)
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Source directories
    backend_dir = os.path.join(base_dir, "ECG FYP", "ECG FYP", "backend")
    cardiac_ml_dir = os.path.join(base_dir, "cardiac_ml")
    setup_script = os.path.join(base_dir, "termux_setup.sh")
    
    output_filename = "ecgenius_backend.zip"
    
    with zipfile.ZipFile(output_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
        # Add Backend files
        if os.path.exists(backend_dir):
            for root, dirs, files in os.walk(backend_dir):
                if '__pycache__' in root or '.venv' in root or '.git' in root:
                    continue
                for file in files:
                    if file == "ecg_monitoring.db" or file.endswith(".pyc"):
                        continue
                        
                    file_path = os.path.join(root, file)
                    # Archive name: backend/app/...
                    # We want the zip to contain a 'backend' folder
                    rel_path = os.path.relpath(file_path, backend_dir)
                    arcname = os.path.join("backend", rel_path)
                    zipf.write(file_path, arcname)
                    print(f"Added: {arcname}")
        else:
            print(f"ERROR: Backend directory not found at {backend_dir}")

        # Add ML files
        if os.path.exists(cardiac_ml_dir):
            for root, dirs, files in os.walk(cardiac_ml_dir):
                 if '__pycache__' in root or 'venv' in root:
                    continue
                 for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.join("cardiac_ml", os.path.relpath(file_path, cardiac_ml_dir))
                    zipf.write(file_path, arcname)
                    print(f"Added: {arcname}")
        else:
            print(f"WARNING: cardiac_ml directory not found at {cardiac_ml_dir}")
            
        # Add Setup Script
        if os.path.exists(setup_script):
            zipf.write(setup_script, "termux_setup.sh")
            print("Added: termux_setup.sh")
        else:
            print(f"WARNING: termux_setup.sh not found at {setup_script}")
            
    print(f"\nSuccessfully created {output_filename} in {base_dir}")

if __name__ == "__main__":
    package_backend()
