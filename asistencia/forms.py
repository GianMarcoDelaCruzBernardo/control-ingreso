from django import forms


class RegistroForm(forms.Form):
    nombres = forms.CharField(
        max_length=100,
        label="Nombres",
        widget=forms.TextInput(attrs={'placeholder': 'Ej: Juan Carlos', 'autofocus': True})
    )
    apellidos = forms.CharField(
        max_length=100,
        label="Apellidos",
        widget=forms.TextInput(attrs={'placeholder': 'Ej: Perez Gomez'})
    )
    dni = forms.CharField(
        max_length=15,
        required=False,
        label="DNI (opcional)",
        widget=forms.TextInput(attrs={'placeholder': 'Opcional por ahora'})
    )