import 'package:flutter/material.dart';

String listBiometricMethodLabel(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => 'Face ID',
  TargetPlatform.android => 'huella',
  _ => 'biometría del dispositivo',
};

String listBiometricUnlockInstruction(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS => 'Usa Face ID para ver su contenido.',
      TargetPlatform.android =>
        'Usa tu huella o el reconocimiento facial para ver su contenido.',
      _ => 'Usa la biometría del dispositivo para ver su contenido.',
    };

String listBiometricSetupInstruction(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS => 'Configura Face ID',
      TargetPlatform.android =>
        'Configura una huella o el reconocimiento facial',
      _ => 'Configura la biometría del dispositivo',
    };

IconData listBiometricIcon(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => Icons.face_rounded,
  _ => Icons.fingerprint_rounded,
};
