from django.db import models

import uuid

# Create your models here.
from django.db import models
from django.contrib.auth.models import User

class Video(models.Model):
    STATUS_CHOICES = [
        ("PENDING", "Pending"),
        ("PROCESSING", "Processing"),
        ("COMPLETED", "Completed"),
        ("FAILED", "Failed"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True, blank=True)
    prompt = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="PENDING")
    final_video_url = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    final_video_gcs_path = models.TextField(null=True, blank=True)

    def __str__(self):
        return f"{self.prompt[:20]}... ({self.status})"
    

class Profile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    profile_picture_url = models.URLField(null=True, blank=True)

    def __str__(self):
        return f"{self.user.username}'s Profile"
    
class Subscription(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='subscription')
    is_active = models.BooleanField(default=False)
    expires_at = models.DateTimeField(null=True, blank=True)
    videos_generated_this_month = models.IntegerField(default=0)
    last_reset_date = models.DateField(null=True, blank=True)

    def __str__(self):
        return f"{self.user.username} — {'active' if self.is_active else 'inactive'}"


class BetaInvite(models.Model):
    code = models.CharField(max_length=50, unique=True)
    is_active = models.BooleanField(default=True)
    # --- NEW: USAGE TRACKING ---
    uses_remaining = models.IntegerField(default=5)  # Starts with 5 lives
    # ---------------------------
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.code} ({self.uses_remaining} uses left)"