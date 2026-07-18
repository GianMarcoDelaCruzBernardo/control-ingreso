import io
import math

import qrcode
from django.conf import settings
from django.contrib.admin.views.decorators import staff_member_required
from django.http import HttpResponse
from django.shortcuts import render
from django.utils import timezone

from .forms import RegistroForm
from .models import RegistroAsistencia, Trabajador


def calcular_distancia_metros(lat1, lng1, lat2, lng2):
    """Distancia entre dos coordenadas usando la formula de haversine (en metros)."""
    radio_tierra = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * radio_tierra * math.asin(math.sqrt(a))


def registrar(request):
    contexto = {}

    if request.method == 'POST':
        form = RegistroForm(request.POST)
        lat = request.POST.get('lat')
        lng = request.POST.get('lng')

        if not lat or not lng:
            contexto['error'] = (
                "No se pudo obtener tu ubicacion. Activa el GPS/ubicacion "
                "del celular y vuelve a intentar."
            )
            contexto['form'] = form
            return render(request, 'asistencia/registrar.html', contexto)

        try:
            lat = float(lat)
            lng = float(lng)
        except ValueError:
            contexto['error'] = "Ubicacion invalida. Intenta nuevamente."
            contexto['form'] = form
            return render(request, 'asistencia/registrar.html', contexto)

        distancia = calcular_distancia_metros(
            lat, lng, settings.COMPANY_LATITUDE, settings.COMPANY_LONGITUDE
        )

        if distancia > settings.ALLOWED_RADIUS_METERS:
            contexto['error'] = (
                f"No te encuentras dentro del establecimiento (distancia: {int(distancia)}m). "
                "No se puede registrar el ingreso/salida desde fuera de la empresa."
            )
            contexto['form'] = form
            return render(request, 'asistencia/registrar.html', contexto)

        if form.is_valid():
            nombres = form.cleaned_data['nombres'].strip().title()
            apellidos = form.cleaned_data['apellidos'].strip().title()
            dni = (form.cleaned_data.get('dni') or '').strip()

            trabajador, _creado = Trabajador.objects.get_or_create(
                nombres__iexact=nombres,
                apellidos__iexact=apellidos,
                defaults={'nombres': nombres, 'apellidos': apellidos, 'dni': dni or None}
            )
            if dni and not trabajador.dni:
                trabajador.dni = dni
                trabajador.save(update_fields=['dni'])

            hoy = timezone.localdate()
            ahora = timezone.now()

            registro_abierto = RegistroAsistencia.objects.filter(
                trabajador=trabajador, fecha=hoy,
                hora_entrada__isnull=False, hora_salida__isnull=True
            ).first()

            if registro_abierto:
                registro_abierto.hora_salida = ahora
                registro_abierto.lat_salida = lat
                registro_abierto.lng_salida = lng
                registro_abierto.save()
                contexto['mensaje'] = (
                    f"SALIDA registrada correctamente a las "
                    f"{timezone.localtime(ahora).strftime('%H:%M:%S')}"
                )
            else:
                RegistroAsistencia.objects.create(
                    trabajador=trabajador, fecha=hoy, hora_entrada=ahora,
                    lat_entrada=lat, lng_entrada=lng
                )
                contexto['mensaje'] = (
                    f"INGRESO registrado correctamente a las "
                    f"{timezone.localtime(ahora).strftime('%H:%M:%S')}"
                )

            contexto['trabajador'] = trabajador
            return render(request, 'asistencia/resultado.html', contexto)

        contexto['form'] = form
        return render(request, 'asistencia/registrar.html', contexto)

    contexto['form'] = RegistroForm()
    return render(request, 'asistencia/registrar.html', contexto)


@staff_member_required
def qr_view(request):
    return render(request, 'asistencia/qr.html')


@staff_member_required
def qr_image(request):
    url = request.build_absolute_uri('/')
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")

    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    return HttpResponse(buffer.getvalue(), content_type='image/png')