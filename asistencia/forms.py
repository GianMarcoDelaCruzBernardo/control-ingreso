from django import forms

from .models import validar_dni


class RegistroForm(forms.Form):
    dni = forms.CharField(
        max_length=15,
        min_length=8,
        label="DNI",
        validators=[validar_dni],
        widget=forms.TextInput(attrs={
            'placeholder': 'Ej: 12345678',
            'autofocus': True,
            'inputmode': 'numeric',
            'id': 'id_dni',
        })
    )
    nombres = forms.CharField(
        max_length=100,
        label="Nombres",
        widget=forms.TextInput(attrs={'placeholder': 'Ej: Juan Carlos', 'id': 'id_nombres'})
    )
    apellidos = forms.CharField(
        max_length=100,
        label="Apellidos",
        widget=forms.TextInput(attrs={'placeholder': 'Ej: Perez Gomez', 'id': 'id_apellidos'})
    )

    def clean_dni(self):
        dni = self.cleaned_data['dni'].strip()
        if not dni.isdigit():
            raise forms.ValidationError('El DNI debe contener solo numeros.')
        return dni
