package com.example.designsystem

/**
 * Pattern for a typed design-token palette in Compose.
 *
 * - Light + dark variants live in one data class.
 * - The active palette is provided through `CompositionLocalProvider`
 *   so any Composable can read `LocalRobodorColors.current.surface`
 *   instead of taking a parameter.
 * - Feature code is forbidden to use `Color(0xFF…)` directly. A
 *   pre-commit lint check fails the build if a hardcoded `Color(`
 *   appears outside this file.
 *
 * Trimmed-down extract from the project's design system. The actual
 * shipped palette covers ~25 colour tokens; this snippet shows the
 * shape, not the values.
 */

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

data class RobodorColorPalette(
    val background: Color,
    val surface: Color,
    val surfaceVariant: Color,
    val border: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val primary: Color,
    val primaryActive: Color,
    val successFg: Color,
    val warningFg: Color,
    val errorFg: Color,
)

private val LightPalette = RobodorColorPalette(
    background = Color(0xFFF6F7FB),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFF0F2F7),
    border = Color(0xFFE3E6EE),
    textPrimary = Color(0xFF111418),
    textSecondary = Color(0xFF54616E),
    textTertiary = Color(0xFF8A95A1),
    primary = Color(0xFF1F4FE8),
    primaryActive = Color(0xFF153AB4),
    successFg = Color(0xFF158F46),
    warningFg = Color(0xFFB37500),
    errorFg = Color(0xFFC62A2A),
)

private val DarkPalette = RobodorColorPalette(
    background = Color(0xFF0E1116),
    surface = Color(0xFF161A21),
    surfaceVariant = Color(0xFF1D232C),
    border = Color(0xFF2A323D),
    textPrimary = Color(0xFFEDEFF3),
    textSecondary = Color(0xFFA9B2BE),
    textTertiary = Color(0xFF6F7884),
    primary = Color(0xFF4F7EFF),
    primaryActive = Color(0xFF3760E3),
    successFg = Color(0xFF3BD37A),
    warningFg = Color(0xFFFFB748),
    errorFg = Color(0xFFFF6363),
)

private val LocalRobodorColors = staticCompositionLocalOf { LightPalette }

object RobodorColors {
    val current: RobodorColorPalette
        @Composable
        @ReadOnlyComposable
        get() = LocalRobodorColors.current
}

@Composable
fun RobodorTheme(
    isDarkMode: Boolean,
    content: @Composable () -> Unit,
) {
    val palette = if (isDarkMode) DarkPalette else LightPalette
    CompositionLocalProvider(LocalRobodorColors provides palette) {
        content()
    }
}
