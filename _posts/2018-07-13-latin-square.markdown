---
layout: post
title:  "Latin Square"
date:   2018-07-13 13:41:29 +0100
categories: c++
image:
  path: /images/latin-square.png
  thumbnail: /images/latin-square.png
---
Looking at the latest video from Presh Talwalkar about solving the Latin square where each row is the first row multiplied by the row number I decided it was time to see if I could remember any C++ and code a solution.

[Can you fiqure out the special 6 digit number?](https://youtu.be/KXOjtmNUSH0)

Include the files standard C++ header files we need

    #include <iostream>
    #include <algorithm>
    #include <vector>
    #include <sstream>
    #include <string>
    #include <iomanip>

    using namespace std;

`CheckDuplicates()` comes from ideas presented in this [Stack Overflow question](https://stackoverflow.com/questions/2860634/checking-for-duplicates-in-a-vector). The function determines whether there are any repeated digits in a vector by sorting the vector and then searching for adjacent items which are the same. Since `std::sort` changes the source vector I’ve created a local copy using the vector constructor function.

    bool CheckDuplicates(vector<unsigned int>* v) {
            vector<unsigned int> c (v->begin(), v->end());
            sort(c.begin(), c.end());
            vector<unsigned int>::iterator it = adjacent_find(c.begin(), c.end());
            if (it == c.end())
                    return false;
            else
                    return true;
    }

On to the body of program

    int main () {

Create a loop which covers all possible six digit numbers. The result can’t be smaller than 123456 and it must be less than 1,000,000 ÷ 6 = 166,666 but change the loop to 0 to 1,000,000 shows that there really aren’t any other solutions.

            for (unsigned int t = 123456; t < 166666; t++) {

I’ll use a vector of vectors to hold the digits of each number.

                    vector< vector<unsigned int>* > square;

This first block of code initialises the first vector with the value from the outer loop. It only adds the value to the square if it doesn’t contain any duplicate digits.

                    {
                            vector<unsigned int>* row = new vector<unsigned int>;
                            unsigned int n = t;
                            for (int i = 0; i < 6; i++) {
                                    row->insert(row->begin(), n % 10);
                                    n /= 10;
                            }
                            if (!CheckDuplicates(row))
                                    square.push_back(row);
                            else
                                    delete row;
                    }

By looking at the size of the `square` vector we can see if we have a row to work with or not. If we do, attempt the multiplication of the first row by 2 through 6 to generate the other rows. As we want full multiplication not just the multiplication of each digit we need to compute the carry at each step and add it on to the next column. If there is a carry into the seventh column then the row can be discarded. Lastly, check for duplicates and if none are found added the number/row to the square. An alternative approach here would be to multiply t and separate the result into the individual digits in a vector as we did above.

                    if (square.size() == 1) {
                            for (unsigned int j = 2; j <= 6; j++) {
                                    unsigned int carry = 0;
                                    vector<unsigned int>* row = new vector<unsigned int>;
                                    for (int i = 5; i >= 0; i--) {
                                            unsigned int n = square.at(0)->at(i) * j + carry;
                                            if (n > 9) {
                                                    carry = n / 10;
                                                    n %= 10;
                                            } else {
                                                    carry = 0;
                                            }
                                            row->insert(row->begin(), n);
                                    }
                                    if (carry) {
                                            delete row;
                                            break;
                                    } else {
                                            if (!CheckDuplicates(row))
                                                    square.push_back(row);
                                            else
                                                    delete row;
                                    }
                            }
                    }

So, if we get to here we have six rows each of different digits in each row. We now need to check for duplication in the columns. This strictly isn’t necessary because only one solution makes it this far, but for the sake of completeness I generate a vector for each column and check it for duplicates. If no duplicates are found then it’s a possible solution.

                    if (square.size() == 6) {
                            bool duplicates = false;
                            for (int i = 5; i >= 0; i--) {
                                    vector<unsigned int> column;
                                    for (vector<unsigned int>* row : square)
                                            column.push_back(row->at(i));
                                    if (CheckDuplicates(&column)) {
                                            duplicates = true;
                                            break;
                                    }
                            }
                            if (!duplicates) {
                                    cout << "\nSolution\n";
                                    for (vector<unsigned int>* row : square) {
                                            for (unsigned int c : *row) {
                                                    cout << c << ' ';
                                            }
                                            cout << '\n';
                                    }
                            }
                    }

Tidy up by deleting each of the row vectors

                    for (vector<unsigned int>* row : square)
                            delete row;
                    square.erase(square.begin(), square.end());
            }

            return 0;
    }

You can download the full version of the code from [Github](https://github.com/mtelvers/LatinSquare)
