from typing import Any, Dict, List, Optional

import typer
from pydantic import EmailStr, ValidationError

logger = get_logger()


def parse_valid_email(value: Optional[str]) -> Optional[EmailStr]:
    if value is None:
        return None

    try:
        email = EmailStr(value)
        return email
    except ValidationError:
        raise typer.BadParameter(f"Invalid email address: {value}")


def parse_tag_cli_options(tags: Optional[List[str]]) -> List[ConfigTag]:
    if not tags:
        return []
    return [ConfigTag(root=t) for t in tags]


def extract_cli_server_details(cli_entries: Optional[List[str]]) -> List[Server]:
    """
    Transforms a list of CLI server options into a list of Server objects.
    Each entry is expected to be a comma-separated string in the form:
    "ip=xxx,ipv6=xxx,name=xxx"
    """
    servers = []
    if not cli_entries:
        return servers

    for entry in cli_entries:
        server_info = {}
        segments = entry.split(",")
        for segment in segments:
            # Ensure the segment has the expected key=value structure.
            if "=" not in segment:
                continue
            key, value = segment.split("=", 1)
            key = key.strip()
            value = value.strip()
            if key == "ip":
                server_info[key] = Product(value.lower())
            elif key == "ipv6":
                server_info[key] = Architecture(value.lower())
            elif key == "name":
                server_info[key] = value
            else:
                raise typer.BadParameter(f"Unexpected key in CLI option: {key}")
        servers.append(Server(**server_info))
    return servers
