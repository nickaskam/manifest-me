from django.shortcuts import render

import datetime
import uuid, os

from rest_framework.decorators import api_view, permission_classes, parser_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from google.cloud import storage
from .engine import generate_manifestation, upload_blob, BUCKET_NAME
from .models import Video, Subscription
from .tasks import enqueue_video_task

from .models import BetaInvite
from django.db import transaction
from django.contrib.auth.models import User
from django.contrib.auth.hashers import make_password
from rest_framework_simplejwt.tokens import RefreshToken

    
@api_view(['GET'])
@permission_classes([])
def health_check(request):
    return Response({"status": "ok"})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def check_profile_status(request):
    user_id = str(request.user.id)
    storage_client = storage.Client()
    bucket = storage_client.bucket(BUCKET_NAME)
    blob = bucket.blob(f"users/{user_id}/profile/avatar.jpg")
    
    if blob.exists():
        # Generate Signed URL (Valid for 1 hour)
        signed_url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.timedelta(hours=1),
            method="GET"
        )
        return Response({"has_image": True, "image_url": signed_url})
    
    return Response({"has_image": False, "image_url": None})

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser]) # Allow file uploads
def upload_profile_image(request):
    """Uploads the user's face."""
    user_id = str(request.user.id)
    file_obj = request.FILES.get('file')
    
    if not file_obj:
        return Response({"error": "No file provided"}, status=400)
    
    # Save temporarily to upload
    temp_path = f"/tmp/{user_id}_avatar.jpg"
    with open(temp_path, 'wb+') as destination:
        for chunk in file_obj.chunks():
            destination.write(chunk)
            
    # Upload to Google Cloud
    # We use 'users/{id}/profile/avatar.jpg' as the standard path
    target_path = f"users/{user_id}/profile/avatar.jpg"
    public_url = upload_blob(BUCKET_NAME, temp_path, target_path)
    
    return Response({
        "status": "success", 
        "image_url": public_url
    })

@api_view(['POST'])
@permission_classes([]) 
def register_user(request):
    # CHANGED: We now look for 'email' instead of 'username'
    email = request.data.get('email')
    password = request.data.get('password')
    invite_code = request.data.get('invite_code')

    if not email or not password or not invite_code:
        return Response({"error": "Missing email, password, or invite code"}, status=400)

    # 🔒 THE BOUNCER (Check Beta Invite)
    try:
        ticket = BetaInvite.objects.get(code=invite_code, is_active=True)
        if ticket.uses_remaining <= 0:
            return Response({"error": "This invite code is fully claimed!"}, status=403)
    except BetaInvite.DoesNotExist:
        return Response({"error": "Invalid Invite Code."}, status=403)

    # CHECK IF EMAIL EXISTS
    # We treat the email as the username
    if User.objects.filter(username=email).exists():
        return Response({"error": "Email already registered"}, status=400)

    # CREATE USER
    # We save the email in BOTH the 'username' and 'email' fields
    user = User.objects.create(
        username=email, 
        email=email,
        password=make_password(password)
    )

    # DECREMENT TICKET
    ticket.uses_remaining -= 1
    if ticket.uses_remaining <= 0:
        ticket.is_active = False
    ticket.save()
    
    print(f"🎉 New User '{email}' joined via code '{invite_code}'")

    # GENERATE TOKEN
    refresh = RefreshToken.for_user(user)
    
    return Response({
        "status": "success",
        "user_id": user.id,
        "access": str(refresh.access_token),
        "refresh": str(refresh)
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_user_videos(request):
    """
    Fetches the list of all manifestation videos for the logged-in user.
    """
    user_id = str(request.user.id)
    prefix = f"users/{user_id}/videos/"
    
    storage_client = storage.Client()
    # Note: ensure BUCKET_NAME is imported from .engine or defined here
    blobs = storage_client.list_blobs(BUCKET_NAME, prefix=prefix)
    
    video_list = []
    for blob in blobs:
        # 2. GENERATE SIGNED URL (The Key Card) 🔑
        # This link works for 1 hour, then expires.
        signed_url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.timedelta(hours=1), 
            method="GET"
        )

        video_list.append({
            "url": signed_url, # <--- Use the key card, not the public link
            "created_at": blob.time_created,
            "name": blob.name.split('/')[-1]
        })
    
    # Sort descending (Newest on top)
    video_list.sort(key=lambda x: x['created_at'], reverse=True)
    
    return Response(video_list)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def manifest_video(request):
    """Waiter: Takes the order and puts it in the queue."""
    # Subscription quota check
    import datetime as dt
    today = dt.date.today()
    sub, _ = Subscription.objects.get_or_create(user=request.user)
    if sub.last_reset_date is None or sub.last_reset_date.month != today.month or sub.last_reset_date.year != today.year:
        sub.videos_generated_this_month = 0
        sub.last_reset_date = today
        sub.save()
    if not sub.is_active:
        return Response({"error": "subscription_required"}, status=403)
    if sub.videos_generated_this_month >= 1:
        return Response({"error": "quota_exceeded"}, status=403)

    prompt = request.data.get('prompt', '').lower()
    theme = request.data.get("theme", "").strip().lower()

    THEME_TO_TEMPLATE = {
        "beach": "beach_manifestation",
        "work": "work_abroad_manifestation",
        "wildlife": "wildlife_retreat_manifestation",
    }

    template = THEME_TO_TEMPLATE.get(theme)
    if not template:
        return Response({"error": "Invalid theme"}, status=400)

    user_id = str(request.user.id)

    # 2. CREATE RECORD (Frozen Model: no template_used field)
    video_obj = Video.objects.create(
        user=request.user,
        prompt=prompt,
        status="PENDING"
    )

    # 3. HANDOFF (We pass the template string directly to the task)
    try:
        enqueue_video_task(video_obj.id, template, user_id)

        sub.videos_generated_this_month += 1
        sub.save()

        return Response({
            "video_id": video_obj.id,
            "status": "PENDING"
        }, status=202)
    except Exception as e:
        print(f"❌ QUEUE ERROR: {e}")
        return Response({"error": str(e)}, status=500)


@api_view(['POST'])
@permission_classes([])
def video_worker(request):
    expected = os.environ.get("WORKER_SECRET")
    got = request.headers.get("X-Worker-Secret")
    if expected and got != expected:
        return Response({"error": "forbidden"}, status=403)

    job_id = request.data.get("job_id")
    template_name = request.data.get("template_name")
    user_id = request.data.get("user_id")

    run_id = str(uuid.uuid4())[:8]
    print(f"[worker {run_id}] START job_id={job_id}")

    # ✅ atomic claim
    with transaction.atomic():
        video_obj = Video.objects.select_for_update().get(id=job_id)
        print(f"[worker {run_id}] status_before={video_obj.status}")

        if video_obj.status == "COMPLETED":
            return Response({"status": "ok", "note": "already completed"}, status=200)

        if video_obj.status == "PROCESSING":
            # IMPORTANT: stop Cloud Tasks retries from re-running Vertex
            return Response({"status": "ok", "note": "already processing"}, status=200)

        # optionally: if FAILED, choose whether to retry or stop
        # if video_obj.status == "FAILED":
        #     return Response({"status": "ok", "note": "already failed"}, status=200)

        video_obj.status = "PROCESSING"
        video_obj.save()

    try:
        print(f"[worker {run_id}] CALLING VERTEX")
        final_url = generate_manifestation(
            video_obj.prompt,
            template_name=template_name,
            user_id=user_id,
        )

        # ⚠️ this field must be TextField or store GCS path instead
        video_obj.final_video_gcs_path = final_url
        video_obj.status = "COMPLETED"
        video_obj.save()

        print(f"[worker {run_id}] DONE")
        return Response({"status": "success"}, status=200)

    except Exception as e:
        video_obj.status = "FAILED"
        video_obj.save()
        print(f"[worker {run_id}] ENGINE ERROR: {e}")
        # If you want retries for transient errors, keep 500.
        # If retries are costing you money, return 200 here and handle retries manually.
        return Response({"error": str(e)}, status=500)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_video_status(request, video_id):
    try:
        video = Video.objects.get(id=video_id, user=request.user)

        signed_url = None

        if video.status == "COMPLETED" and video.final_video_gcs_path:
            storage_client = storage.Client()
            bucket = storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(video.final_video_gcs_path)

            signed_url = blob.generate_signed_url(
                version="v4",
                expiration=datetime.timedelta(hours=1),
                method="GET"
            )

        return Response({
            "status": video.status,
            "video_url": signed_url
        })

    except Video.DoesNotExist:
        return Response({"error": "Video not found"}, status=404)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_subscription_status(request):
    import datetime as dt
    today = dt.date.today()
    sub, _ = Subscription.objects.get_or_create(user=request.user)
    if sub.last_reset_date is None or sub.last_reset_date.month != today.month or sub.last_reset_date.year != today.year:
        sub.videos_generated_this_month = 0
        sub.last_reset_date = today
        sub.save()
    videos_remaining = max(0, 1 - sub.videos_generated_this_month) if sub.is_active else 0
    return Response({
        "is_active": sub.is_active,
        "videos_remaining": videos_remaining,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def verify_subscription(request):
    """Receives a StoreKit 2 transaction ID from the iOS app and activates the subscription."""
    transaction_id = request.data.get('transaction_id')
    expires_at_str = request.data.get('expires_at')  # ISO 8601 string from StoreKit

    if not transaction_id:
        return Response({"error": "Missing transaction_id"}, status=400)

    import datetime as dt
    sub, _ = Subscription.objects.get_or_create(user=request.user)
    sub.is_active = True
    if expires_at_str:
        try:
            sub.expires_at = dt.datetime.fromisoformat(expires_at_str)
        except ValueError:
            pass
    sub.save()

    return Response({"status": "activated"})