<?php

declare(strict_types=1);

namespace App\Support;

/** A PHP port of the reference app's `formatRelativeTime`/`formatDateTime` (src/lib/utils.ts). */
final class TimeFormat
{
    public static function relative(?string $isoDate): string
    {
        if ($isoDate === null || $isoDate === '') {
            return '';
        }

        $timestamp = strtotime($isoDate);
        if ($timestamp === false) {
            return '';
        }

        $diffSeconds = time() - $timestamp;
        if ($diffSeconds < 5) {
            return 'just now';
        }
        if ($diffSeconds < 60) {
            return "{$diffSeconds}s ago";
        }

        $diffMinutes = (int) round($diffSeconds / 60);
        if ($diffMinutes < 60) {
            return "{$diffMinutes}m ago";
        }

        $diffHours = (int) round($diffMinutes / 60);
        if ($diffHours < 24) {
            return "{$diffHours}h ago";
        }

        $diffDays = (int) round($diffHours / 24);
        if ($diffDays < 7) {
            return "{$diffDays}d ago";
        }

        return date('M j, Y', $timestamp);
    }

    /** Approximates `Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" })`. */
    public static function dateTime(?string $isoDate): string
    {
        if ($isoDate === null || $isoDate === '') {
            return '';
        }

        $timestamp = strtotime($isoDate);
        if ($timestamp === false) {
            return '';
        }

        return date('M j, Y g:i A', $timestamp);
    }
}
