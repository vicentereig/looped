def factorial(n)
  return 1 if n == 0
  n * factorial(n - 1)
end

puts factorial(1) # Output: 1