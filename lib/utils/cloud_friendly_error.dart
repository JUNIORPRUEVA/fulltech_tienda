import 'dart:async';
import 'dart:io';

/// Convierte errores tecnicos del cloud en mensajes claros para el usuario.
///
/// Nota: intencionalmente NO muestra detalles internos (URLs, status codes, etc.).
String cloudFriendlyReason(Object error) {
  if (error is TimeoutException) {
    return 'Sin conexion o el servidor esta lento. Revisa tu internet e intenta nuevamente.';
  }

  if (error is SocketException) {
    return 'Sin conexion a internet. Revisa tu red.';
  }

  final msg = error.toString().trim().toLowerCase();

  if (msg.contains('validation_error') || msg.contains('invalid request')) {
    if (msg.contains('password') && (msg.contains('>=8') || msg.contains('minimum":8') || msg.contains('too small'))) {
      return 'La contrasena debe tener minimo 8 caracteres para la nube.';
    }
    return 'Datos invalidos. Revisa usuario y contrasena.';
  }

  if (msg.contains('blocked') || msg.contains('bloque')) {
    return 'Usuario bloqueado.';
  }

  // Casos tipicos del backend.
  if (msg.contains('401') ||
      msg.contains('unauthorized') ||
      msg.contains('credenciales') ||
      msg.contains('invalid credentials')) {
    return 'Usuario o contrasena incorrectos.';
  }

  if (msg.contains('409') ||
      msg.contains('email already in use') ||
      msg.contains('already in use') ||
      msg.contains('already') ||
      msg.contains('existe')) {
    return 'Ese usuario ya existe en la nube. Si no es tu cuenta, usa otro.';
  }

  if (msg.contains('invalid refresh token')) {
    return 'La sesion de la nube expiro. Vuelve a iniciar sesion.';
  }

  if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
    return 'La nube esta teniendo problemas. Intenta mas tarde.';
  }

  return 'No se pudo conectar a la nube. Revisa tu usuario, contrasena e internet.';
}
