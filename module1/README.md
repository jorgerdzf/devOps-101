# Lab 1 - Bash Shell Scripting

## Shell Script to do a line count over files


Create a Bash Shell script using functions to count the number of lines in text files located in the current directory when:
They belong to an owner OR
When were created in a specific month

The shell script should accept the following options:

-o <owner>
To select files where the owner is <owner>

-m <month>
To select files where the creation month is <month>

When receiving invalid arguments, show help 

Invalid arguments:

./countlines.sh

./countlines.sh -o owner -m month

Other arguments
./countlines.sh -x owner
