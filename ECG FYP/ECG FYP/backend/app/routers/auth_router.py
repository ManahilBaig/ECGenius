from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from google.cloud import firestore
from datetime import datetime

from app.db.session import get_db
from app.models.schemas import Token, UserCreate, UserOut
from app.auth import hash_password, verify_password, create_token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=UserOut)
async def register(data: UserCreate, db: firestore.Client = Depends(get_db)):
    # Check if user already exists
    users_ref = db.collection('users')
    query = users_ref.where('email', '==', data.email).limit(1)
    docs = query.stream()
    existing_user = None
    for doc in docs:
        existing_user = doc
        break

    if existing_user:
        raise HTTPException(400, "Email already registered")

    # Create new user document
    user_data = {
        'email': data.email,
        'hashed_password': hash_password(data.password),
        'full_name': data.full_name,
        'is_active': True,
        'created_at': datetime.utcnow()
    }

    doc_ref = users_ref.document()
    doc_ref.set(user_data)

    # Return user data with generated ID
    user_out = UserOut(
        id=doc_ref.id,
        email=data.email,
        full_name=data.full_name,
        is_active=True,
        created_at=user_data['created_at']
    )
    return user_out


@router.post("/login", response_model=Token)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: firestore.Client = Depends(get_db),
):
    # form.username used as email for compatibility with OAuth2 form
    users_ref = db.collection('users')
    query = users_ref.where('email', '==', form.username).limit(1)
    docs = query.stream()
    user_doc = None
    for doc in docs:
        user_doc = doc
        break

    if not user_doc or not verify_password(form.password, user_doc.to_dict()['hashed_password']):
        raise HTTPException(401, "Invalid email or password")

    user_data = user_doc.to_dict()
    return Token(access_token=create_token(user_doc.id), token_type="bearer")
