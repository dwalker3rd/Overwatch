# $global:Catalog.Product += @{ BgInfo = 
#     [Product]@{
#         Id = "BgInfo"
#         Name = "BgInfo"
#         DisplayName = "BgInfo"
#         Description = "Updates custom content for the Azure BgInfo VM extension."
#         Publisher = "Walker Analytics Consulting"
#         Log = "BgInfo"
#         HasTask = $true
#         Installation = @{
#             Prerequisite = @{
#                 Cloud = @("Azure")
#             }
#         }
#     }
# }