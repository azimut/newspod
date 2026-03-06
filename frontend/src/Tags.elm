module Tags exposing
    ( Tags
    , fromList
    , intersect
    , isSelected
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
    , visible : Set.Set String
    }


toList : Tags -> List String
toList tags =
    Set.toList tags.visible


fromList : List String -> Tags
fromList rawTags =
    { names = rawTags
    , selected = Set.empty
    , visible = Set.fromList rawTags
    }


reset : Tags -> Tags
reset tags =
    { tags
        | selected = Set.empty
        , visible = Set.fromList tags.names
    }


toggleTag : Tags -> String -> Tags
toggleTag tags tagName =
    if Set.member tagName tags.selected then
        { tags | selected = Set.remove tagName tags.selected }

    else
        { tags | selected = Set.insert tagName tags.selected }


setVisible : Tags -> Set.Set String -> Tags
setVisible tags visible =
    { tags | visible = visible }

isVisible : Tags -> String -> Bool
isVisible tags tagName =
    Set.member tagName tags.visible


isSelected : Tags -> String -> Bool
isSelected tags tagName =
    Set.member tagName tags.selected


intersect : Tags -> Set.Set String -> Bool
intersect tags targetTags =
    not <| Set.isEmpty <| Set.intersect tags.selected targetTags


noneSelected : Tags -> Bool
noneSelected tags =
    Set.isEmpty tags.selected
