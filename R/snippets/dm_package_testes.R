a <- tibble( key = 1:5, value = LETTERS[1:5])
b <- tibble( key = 6:10, value = letters[6:10])

db1 <- dm(a,b) |> 
  dm_add_pk(a, key) |> 
  dm_add_pk(b, key) |> 
  dm_add_fk(b, key, a)

db1$a
db2$b

a <- tibble(key = 5:10, value = letters[5:10])
b <- tibble(key = 1:6, value = LETTERS[1:6])

db2 <- dm(a,b) |> 
  dm_add_pk(a, key) |> 
  dm_add_pk(b, key) |> 
  dm_add_fk(b, key, a)


db3 <- dm_rows_insert(db1, db2)
db3 <- dm_rows_append(db1, db2)
db3 <- dm_rows_update(db1, db2)
db3 <- dm_rows_upsert(db1, db2)

db1$a
db2$a
db3$a



?LETTERS
