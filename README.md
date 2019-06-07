# Mail Parser

Lua scripts to parse mail messages, plain or in MIME format.

## Shell Script `mail_parser*.sh`

### Usage

*	`./mail_parser-nix.sh <mail-message-file> <output-directory> [first-content-type] [number-of-input-lines]`

Parse a give mail message file and extracts its content into a given output directory.
Optionally, the parsing and the extraction can stop after:

*	the first (full pattern-matching) occurence of a given MIME content type (i.e., it can be a lua RE pattern without '^' and '$' that are implicit),
*	the reading a given number of input lines (the processing of a content starting on a line before the given number will be finished).

### Example

~~~
./mail_parser-nix.sh sample.eml export_dir 'text/.*' 1000
~~~

## License

All files are subjects of licensing according to the [GNU General Public License version 3.0 (GPLv3)](https://www.gnu.org/licenses/gpl-3.0.html).
