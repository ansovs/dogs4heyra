# dogs4heyra

Extracts dog breed data from [The Dog API](https://api.thedogapi.com/v1/breeds).

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

An API key is required for the `/breeds` endpoint. Get a free one at
https://thedogapi.com and set it via:

```bash
export DOG_API_KEY=your-key-here
```

## Usage

```bash
dogs4heyra-extract                          # writes breeds.json
dogs4heyra-extract -o breeds.csv             # writes CSV instead
dogs4heyra-extract -o data/all_breeds.json   # any output path
```

Or as a library:

```python
from dogs4heyra.extract import fetch_breeds

breeds = fetch_breeds()
```

## Tests

```bash
pytest
```
