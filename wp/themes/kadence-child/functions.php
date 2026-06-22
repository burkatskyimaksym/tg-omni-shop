<?php
/**
 * Kadence Child Theme
 */

// Enqueue parent + child theme styles
add_action( 'wp_enqueue_scripts', function () {
    wp_enqueue_style( 'kadence-parent', get_template_directory_uri() . '/style.css' );
    wp_enqueue_style(
        'kadence-child',
        get_stylesheet_directory_uri() . '/style.css',
        ['kadence-parent'],
        // Auto-bust cache whenever the CSS file changes
        filemtime( get_stylesheet_directory() . '/style.css' )
    );
}, 20 );
