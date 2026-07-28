# Django / DRF — Review Guide

## When to load

Any `.py` file with `django.` / `rest_framework.` imports, or project with `manage.py`.

## Top review heuristics

### Security

- Raw SQL with string formatting → `[blocking]` "Use `.raw()` with params or ORM."
- `User.objects.get(...)` without scoping to `request.user` → `[blocking]` "IDOR."
- `@csrf_exempt` on a state-changing endpoint → `[blocking]` unless documented.
- `SECRET_KEY` in code / settings → `[blocking]`.
- `DEBUG = True` in production settings → `[blocking]`.
- `ALLOWED_HOSTS = ['*']` → `[blocking]`.
- File upload endpoint without size/type validation → `[important]`.

### ORM / database

- N+1 in templates or views (FK accessed in a loop without `select_related`/ `prefetch_related`) → `[blocking]`.
- `.all()` then filtering in Python → `[important]` "Filter in DB."
- `.count()` on a QuerySet that's already been evaluated → `[important]` "Use `len(qs)`."
- Missing migrations for model changes → `[blocking]`.
- Migration with `atomic = False` on a large data migration → `[suggestion]` "Sometimes needed but document why."
- Index missing on a FK or commonly-filtered column → `[important]`.

### Serializers (DRF)

- Serializer with `fields = '__all__'` on a model with sensitive fields (password, ssn, internal id) → `[blocking]`.
- `Meta.read_only_fields` missing on fields the client shouldn't write → `[important]`.
- Custom `create`/`update` that doesn't call `super().create/update` and bypasses validation → `[important]`.

### Views / ViewSets

- ViewSet with custom action lacking permissions → `[blocking]`.
- Function-based view that should be class-based for consistency → `[suggestion]`.
- `pagination_class = None` on a list endpoint that can return many rows → `[important]`.

### Async views

- Async view calling sync ORM without `sync_to_async` → `[blocking]`.
- `aget`/`afilter` available but sync used in async context → `[important]`.

### Settings / config

- Settings imported via `from django.conf import settings` inside hot paths → `[suggestion]`.
- Hard-coded paths to media/static instead of settings → `[important]`.

## See also

- [python.md](./code-review-guide.md).
- Upstream: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/django.md>.
