from django.urls import path

from . import views

urlpatterns = [
    path('', views.registrar, name='registrar'),
    path('buscar-dni/<str:dni>/', views.buscar_trabajador, name='buscar_trabajador'),
    path('qr/', views.qr_view, name='qr_view'),
    path('qr/imagen/', views.qr_image, name='qr_image'),
    path('reportes/', views.reporte_asistencia, name='reporte_asistencia'),
    path('reportes/excel/', views.exportar_reporte_excel, name='exportar_reporte_excel'),
]