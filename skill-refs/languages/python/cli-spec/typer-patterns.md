# Typer / Click Patterns (Python)

> Prerequisite: [General CLI principles](../../../cli-design/) for architecture, logging, errors, config, coding style. This file is the Python-with-Typer implementation guide.

Practical Typer/Click patterns: typed CLI option declarations, Pydantic validators, multi-value parsing.

## Path option

Validate path existence and type at parse time:

```python
config_path: Annotated[
    Optional[Path],
    typer.Option(
        exists=True,
        file_okay=False,
        dir_okay=True,
        readable=True,
        resolve_path=True,
        help="Path to the configuration directory that holds the configuration files.",
    ),
] = None,
some_dir: Optional[Path] = typer.Option(
    None,
    help="Dir to save something",
),
list_of_dirs: Optional[List[Path]] = typer.Option(
    None,
    help="List of dirs",
),
email: Optional[str] = typer.Option(
    None,
    help="Email address.",
    callback=parse_valid_email,
),
```

```python
def parse_valid_email(value: Optional[str]) -> Optional[EmailStr]:
    if value is None:
        return None

    try:
        email = EmailStr(value)
        return email
    except ValidationError:
        raise typer.BadParameter(f"Invalid email address: {value}")
```

---

Multiple "tags" with pydantic special type/model

```python
def main(
    num: Optional[int] = typer.Option(
        None,
        "--num",
        "-n",
        help="Number of images to test from PINT.",
        min=1,
    ),
    tags: List[str] = typer.Option(
        None,
        "--tag",
        "-t",
        help="Multiple...",
        callback=parse_tag_cli_options,
    ),
) -> None:
```

```python
def parse_tag_cli_options(tags: Optional[List[str]]) -> List[ConfigTag]:
    if not tags:
        return []
    return [ConfigTag(root=t) for t in tags]
```

```python
class ConfigTag(RootModel[str]):
    @model_validator(mode="before")
    def pre_process(cls, value: str) -> str:
        return value.strip().lower()


class ConfigTags(RootModel[List[ConfigTag]]):
    @model_validator(mode="before")
    def pre_process(cls, values: List[str]) -> List[str]:
        return values or ["default"]

    def __len__(self) -> int:
        return len(self.root)
```
