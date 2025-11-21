from pydantic import BaseModel, Field, EmailStr
from typing import List, Optional

ALLOWED_ROLES = {"admin", "content_editor", "instructor"}

class RoleUpdate(BaseModel):
    email: EmailStr
    roles: List[str]

class UserOut(BaseModel):
    id: str
    email: Optional[str] = None
    displayName: Optional[str] = None
    photoURL: Optional[str] = None
    roles: List[str] = []
    locale: Optional[str] = "en"
    createdAt: Optional[str] = None
    lastActiveAt: Optional[str] = None

class CreateUserIn(BaseModel):
    email: EmailStr
    password: str
    displayName: Optional[str] = None
    roles: List[str] = []

class CourseIn(BaseModel):
    title: str
    summary: Optional[str] = None
    difficulty: Optional[str] = Field(None, description="beginner|intermediate|advanced")
    tags: List[str] = []
    published: bool = False
    order: int = 0
    locale: str = "en"

class CoursePatch(BaseModel):
    title: Optional[str] = None
    summary: Optional[str] = None
    difficulty: Optional[str] = None
    tags: Optional[List[str]] = None
    published: Optional[bool] = None
    order: Optional[int] = None
    locale: Optional[str] = None
    isArchive: Optional[bool] = None

class CourseOut(CourseIn):
    id: str
    isArchive: bool = False

class ModuleIn(BaseModel):
    courseId: str
    title: str
    summary: Optional[str] = None
    order: int = 0
    published: bool = False

class ModulePatch(BaseModel):
    title: Optional[str] = None
    summary: Optional[str] = None
    order: Optional[int] = None
    published: Optional[bool] = None

class ModuleOut(ModuleIn):
    id: str

class LessonIn(BaseModel):
    moduleId: str
    title: str
    transcript: Optional[str] = None
    mediaRefs: List[str] = []  # store /media paths
    order: int = 0
    published: bool = False

class LessonPatch(BaseModel):
    title: Optional[str] = None
    transcript: Optional[str] = None
    mediaRefs: Optional[List[str]] = None
    order: Optional[int] = None
    published: Optional[bool] = None

class LessonOut(LessonIn):
    id: str