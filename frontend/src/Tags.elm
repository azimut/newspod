module Tags exposing
    ( Tags
    , fromList
    , isDeselected
    , isSelected
    , match
    , noneSelected
    , reset
    , setVisible
    , toList
    , toggleTag
    )

import Set


type alias Tags =
    { names : List String
    , selected : Set.Set String
    , deselected : Set.Set String
    , visible : Set.Set String
    }


toList : Tags -> List String
toList tags =
    Set.toList tags.visible


fromList : List String -> Tags
fromList rawTags =
    { names = rawTags
    , selected = Set.empty
    , deselected = Set.empty
    , visible = Set.fromList rawTags
    }


reset : Tags -> Tags
reset tags =
    { tags
        | selected = Set.empty
        , deselected = Set.empty
        , visible = Set.fromList tags.names
    }


toggleTag : Tags -> String -> Tags
toggleTag tags tagName =
    if Set.member tagName tags.selected then
        { tags
            | selected = Set.remove tagName tags.selected
            , deselected = Set.insert tagName tags.deselected
        }

    else if Set.member tagName tags.deselected then
        { tags | deselected = Set.remove tagName tags.deselected }

    else
        { tags | selected = Set.insert tagName tags.selected }


setVisible : Tags -> Set.Set String -> Tags
setVisible tags visible =
    { tags | visible = visible }


isSelected : Tags -> String -> Bool
isSelected tags tagName =
    Set.member tagName tags.selected


isDeselected : Tags -> String -> Bool
isDeselected tags tagName =
    Set.member tagName tags.deselected


match : Tags -> Set.Set String -> Bool
match tags feedTags =
    let
        deselectedTags =
            Set.diff feedTags tags.deselected
    in
    if Set.isEmpty tags.selected then
        not <| Set.isEmpty <| deselectedTags

    else
        not <| Set.isEmpty <| Set.intersect deselectedTags tags.selected


noneSelected : Tags -> Bool
noneSelected tags =
    Set.isEmpty tags.selected && Set.isEmpty tags.deselected
