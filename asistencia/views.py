import datetime
import io
import math

import qrcode
from django.conf import settings
from django.contrib.admin.views.decorators import staff_member_required
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.utils import timezone

from .forms import RegistroForm
from .models import RegistroAsistencia, Trabajador
from .utils_excel import generar_reporte_excel


def calcular_distancia_metros(lat1, lng1, lat2, lng2):
    """Distancia entre dos coordenadas usando la formula de haversine (en metros)."""
    radio_tierra = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * radio_tierra * math.asin(math.sqrt(a))


def _registro_abierto_hoy(trabajador):
    """Devuelve el registro de hoy que tiene ingreso pero no salida, si existe."""
    hoy = timezone.localdate()
    return RegistroAsistencia.objects.filter(
        trabajador=trabajador, fecha=hoy,
        hora_entrada__isnull=False, hora_salida__isnull=True
    ).first()


def buscar_trabajador(request, dni):
    """Endpoint AJAX: dado un DNI, devuelve nombres/apellidos guardados y si le toca
    marcar ENTRADA o SALIDA hoy. Permite autocompletar el formulario."""
    dni = (dni or '').strip()

    if not dni.isdigit() or not (8 <= len(dni) <= 15):
        return JsonResponse({'error': 'DNI invalido.'}, status=400)

    trabajador = Trabajador.objects.filter(dni=dni).first()
    if not trabajador:
        return JsonResponse({'encontrado': False})

    accion = 'salida' if _registro_abierto_hoy(trabajador) else 'entrada'
    return JsonResponse({
        'encontrado': True,
        'nombres': trabajador.nombres,
        'apellidos': trabajador.apellidos,
        'accion': accion,
    })


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
            dni = form.cleaned_data['dni'].strip()
            nombres = form.cleaned_data['nombres'].strip().title()
            apellidos = form.cleaned_data['apellidos'].strip().title()

            trabajador, creado = Trabajador.objects.get_or_create(
                dni=dni,
                defaults={'nombres': nombres, 'apellidos': apellidos}
            )
            if not creado and (trabajador.nombres != nombres or trabajador.apellidos != apellidos):
                # El trabajador ya existia con ese DNI pero corrigio su nombre: actualizamos.
                trabajador.nombres = nombres
                trabajador.apellidos = apellidos
                trabajador.save(update_fields=['nombres', 'apellidos'])

            hoy = timezone.localdate()
            ahora = timezone.now()

            registro_abierto = _registro_abierto_hoy(trabajador)

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


def _rango_periodo(periodo, fecha_str):
    """Calcula (inicio, fin, etiqueta, fecha_base) segun 'dia' | 'semana' | 'mes'."""
    hoy = timezone.localdate()
    if fecha_str:
        try:
            fecha_base = datetime.datetime.strptime(fecha_str, '%Y-%m-%d').date()
        except ValueError:
            fecha_base = hoy
    else:
        fecha_base = hoy

    if periodo == 'semana':
        inicio = fecha_base - datetime.timedelta(days=fecha_base.weekday())
        fin = inicio + datetime.timedelta(days=6)
        etiqueta = f"Semana del {inicio.strftime('%d/%m/%Y')} al {fin.strftime('%d/%m/%Y')}"
    elif periodo == 'mes':
        inicio = fecha_base.replace(day=1)
        if inicio.month == 12:
            fin = inicio.replace(year=inicio.year + 1, month=1, day=1) - datetime.timedelta(days=1)
        else:
            fin = inicio.replace(month=inicio.month + 1, day=1) - datetime.timedelta(days=1)
        etiqueta = f"Mes de {inicio.strftime('%B %Y')}"
    else:
        periodo = 'dia'
        inicio = fin = fecha_base
        etiqueta = f"Dia {fecha_base.strftime('%d/%m/%Y')}"

    return inicio, fin, etiqueta, fecha_base


@staff_member_required
def reporte_asistencia(request):
    periodo = request.GET.get('periodo', 'dia')
    fecha_str = request.GET.get('fecha')
    inicio, fin, etiqueta, fecha_base = _rango_periodo(periodo, fecha_str)

    registros = RegistroAsistencia.objects.select_related('trabajador').filter(
        fecha__gte=inicio, fecha__lte=fin
    ).order_by('-fecha', 'trabajador__apellidos')

    total = registros.count()
    en_curso = registros.filter(hora_salida__isnull=True, hora_entrada__isnull=False).count()
    completados = registros.filter(hora_salida__isnull=False).count()
    trabajadores_unicos = registros.values('trabajador').distinct().count()

    contexto = {
        'registros': registros,
        'periodo': periodo,
        'fecha_base': fecha_base.strftime('%Y-%m-%d'),
        'etiqueta': etiqueta,
        'total': total,
        'en_curso': en_curso,
        'completados': completados,
        'trabajadores_unicos': trabajadores_unicos,
    }
    return render(request, 'asistencia/reporte.html', contexto)


@staff_member_required
def exportar_reporte_excel(request):
    periodo = request.GET.get('periodo', 'dia')
    fecha_str = request.GET.get('fecha')
    inicio, fin, etiqueta, _ = _rango_periodo(periodo, fecha_str)

    registros = RegistroAsistencia.objects.select_related('trabajador').filter(
        fecha__gte=inicio, fecha__lte=fin
    )
    return generar_reporte_excel(registros, etiqueta, filename_prefix=f"control_ingreso_{periodo}")
