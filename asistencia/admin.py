from django.contrib import admin
from unfold.admin import ModelAdmin
from django.utils import timezone
from django.utils.html import format_html

from .models import RegistroAsistencia, Trabajador
from .utils_excel import generar_reporte_excel


@admin.register(Trabajador)
class TrabajadorAdmin(ModelAdmin):
    list_display = ('apellidos', 'nombres', 'dni', 'activo', 'creado')
    list_filter = ('activo',)
    search_fields = ('nombres', 'apellidos', 'dni')


def exportar_excel(modeladmin, request, queryset):
    return generar_reporte_excel(queryset, "Seleccion manual desde el admin", filename_prefix="control_ingreso_seleccion")


exportar_excel.short_description = "Exportar seleccionados a Excel (profesional)"


@admin.register(RegistroAsistencia)
class RegistroAsistenciaAdmin(ModelAdmin):
    change_list_template = "admin/asistencia/registroasistencia/change_list.html"
    list_display = (
        'trabajador', 'fecha', 'hora_entrada_local',
        'hora_salida_local', 'horas_trabajadas', 'estado_coloreado'
    )
    list_filter = ('fecha',)
    search_fields = ('trabajador__nombres', 'trabajador__apellidos', 'trabajador__dni')
    date_hierarchy = 'fecha'
    actions = [exportar_excel]

    def hora_entrada_local(self, obj):
        return timezone.localtime(obj.hora_entrada).strftime('%H:%M:%S') if obj.hora_entrada else '-'
    hora_entrada_local.short_description = 'Hora Entrada'

    def hora_salida_local(self, obj):
        return timezone.localtime(obj.hora_salida).strftime('%H:%M:%S') if obj.hora_salida else '-'
    hora_salida_local.short_description = 'Hora Salida'

    def estado_coloreado(self, obj):
        colores = {'EN CURSO': 'orange', 'COMPLETADO': 'green', 'SIN INGRESO': 'red'}
        color = colores.get(obj.estado, 'black')
        return format_html('<strong style="color: {};">{}</strong>', color, obj.estado)
    estado_coloreado.short_description = 'Estado'
