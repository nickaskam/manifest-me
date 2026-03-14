from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from .views import manifest_video, check_profile_status, upload_profile_image, register_user, get_user_videos, get_video_status, video_worker, health_check, verify_subscription, get_subscription_status

print("🔥 DEBUG: URLs loading with Legacy Support...")

urlpatterns = [
    # --- AUTHENTICATION ---
    path('token/pair/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('register/', register_user, name='register'),
    path('login/', TokenObtainPairView.as_view(), name='login'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # --- FEATURES ---
    # User-Facing: Kicks off the process and returns a 202
    path('manifest/', manifest_video, name='manifest_video'),
    
    # User-Facing: The app pings this to see if the video is ready
    path('videos/status/<uuid:video_id>/', get_video_status, name='get_video_status'),
    
    # Internal: Google Cloud Tasks calls this to run the 5-minute engine
    path('worker/', video_worker, name='video_worker'),

    path('profile/status/', check_profile_status, name='profile_status'),
    path('profile/upload/', upload_profile_image, name='profile_upload'),
    path('videos/', get_user_videos, name='get_videos'),

    # --- HEALTH ---
    path('health/', health_check, name='health_check'),

    # --- SUBSCRIPTION ---
    path('subscription/verify/', verify_subscription, name='verify_subscription'),
    path('subscription/status/', get_subscription_status, name='subscription_status'),
]