export 'app_fonts.dart';
export 'app_themes.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Optional heading font (Plan/01 §6): Prompt for big titles.
TextStyle headingStyle(BuildContext context) =>
    GoogleFonts.prompt(textStyle: Theme.of(context).textTheme.titleLarge);
