# Nginx Site Configuration Directory

This directory contains individual site configurations that are automatically included by the main `nginx.conf` file.

## File Naming Convention

Site configuration files should be named: `{domain}.conf`

Examples:
- `example.com.conf`
- `mysite.org.conf`
- `blog.example.com.conf`

## Template

Use the `site-template.conf` file as a starting point for new sites. Copy it and rename it to match your domain.

## Management

Use the `manage-sites.sh` script to automatically create, update, or remove site configurations.

## Important Notes

- Each file should contain exactly one `server` block
- The `server_name` directive should match the filename (without .conf)
- Files are automatically reloaded when nginx is restarted
- Invalid configurations will prevent nginx from starting 