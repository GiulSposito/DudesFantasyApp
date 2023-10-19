devtools::install_github("bergant/rapiclient")

library(rapiclient)

pet_api <- get_api(url = "http://petstore.swagger.io/v2/swagger.json")
operations <- get_operations(pet_api)
schemas <- get_schemas(pet_api)

res <- operations$getPetById(petId = 1)

res$status_code

res <- operations$getInventory()

res$status_code

res |> str()

content(res)
