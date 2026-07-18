import os
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Crea o actualiza el superusuario leyendo variables de entorno (idempotente, seguro para correr en cada deploy)."

    def handle(self, *args, **options):
        User = get_user_model()

        username = os.environ.get("DJANGO_SUPERUSER_USERNAME")
        password = os.environ.get("DJANGO_SUPERUSER_PASSWORD")
        email = os.environ.get("DJANGO_SUPERUSER_EMAIL", "")

        if not username or not password:
            self.stdout.write(self.style.WARNING(
                "DJANGO_SUPERUSER_USERNAME o DJANGO_SUPERUSER_PASSWORD no estan definidas. "
                "Se omite la creacion del superusuario."
            ))
            return

        user, created = User.objects.get_or_create(
            username=username,
            defaults={"email": email, "is_staff": True, "is_superuser": True},
        )

        if created:
            user.set_password(password)
            user.is_staff = True
            user.is_superuser = True
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Superusuario '{username}' creado."))
        else:
            # Ya existe: nos aseguramos de que siga siendo superusuario y
            # actualizamos la contrasena por si la cambiaste en las env vars.
            user.set_password(password)
            user.is_staff = True
            user.is_superuser = True
            user.email = email or user.email
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Superusuario '{username}' actualizado."))
