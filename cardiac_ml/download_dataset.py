import kaggle
import os

# Set Kaggle API credentials
os.environ['KAGGLE_USERNAME'] = 'manahilbaig'
os.environ['KAGGLE_KEY'] = '581ff4d96049cc59e14df1607ad9ebba'

# Download the dataset
dataset_slug = 'akki2703/ecg-of-cardiac-ailments-dataset'
kaggle.api.dataset_download_files(dataset_slug, path='.', unzip=True)

print("Dataset downloaded and extracted successfully!")
