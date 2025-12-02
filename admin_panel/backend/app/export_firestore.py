import firebase_admin
from firebase_admin import credentials, firestore
import os

# Load credentials
cred = credentials.Certificate("lipreadapp-441dd04e8b92.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def is_document_path(path: str) -> bool:
    # Document paths have even number of elements: col/doc
    return len([p for p in path.split('/') if p]) % 2 == 0

def is_collection_path(path: str) -> bool:
    # Collection paths have odd number of elements: col/doc/col
    return len([p for p in path.split('/') if p]) % 2 == 1

def print_structure(path="", level=0):
    indent = "  " * level

    if path == "":
        # Top-level collections
        collections = db.collections()
        for col in collections:
            print(f"{indent}Collection: {col.id}")
            print_structure(col.id, level + 1)
        return

    parts = [p for p in path.split('/') if p]

    if is_collection_path(path):
        # We are pointing to a COLLECTION
        col_ref = db.collection(path)
        for doc in col_ref.stream():
            print(f"{indent}Document: {doc.id}")
            data = doc.to_dict() or {}
            for key, value in data.items():
                print(f"{indent}  Field: {key} ({type(value).__name__})")
            # Explore subcollections under this doc
            doc_path = f"{path}/{doc.id}"
            print_structure(doc_path, level + 1)

    elif is_document_path(path):
        # We are pointing to a DOCUMENT
        doc_ref = db.document(path)
        subcollections = doc_ref.collections()
        for sub in subcollections:
            print(f"{indent}Subcollection: {sub.id}")
            print_structure(f"{path}/{sub.id}", level + 1)

print_structure()