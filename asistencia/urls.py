from django.urls import path

from . import views

urlpatterns = [
    path('', views.registrar, name='registrar'),
    path('qr/', views.qr_view, name='qr_view'),
    path('qr/imagen/', views.qr_image, name='qr_image'),
]