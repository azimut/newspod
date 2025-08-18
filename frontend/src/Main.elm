port module Main exposing (..)

import Browser
import Filesize
import Html exposing (Html, a, article, button, details, div, footer, form, h1, header, img, input, li, main_, span, summary, text, time, ul)
import Html.Attributes exposing (attribute, autocomplete, autofocus, class, disabled, href, id, maxlength, minlength, name, placeholder, size, src, style, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit, stopPropagationOn)
import Http
import Json.Decode as JD
import List.Extra
import Loaders
import Markdown
import Maybe.Extra
import OrderedDict exposing (OrderedDict)
import Set
import String exposing (fromInt)
import Task
import Time exposing (millisToPosix)
import Time.Distance exposing (inWords)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Model =
    { feeds : List Feed
    , entries : OrderedDict Int (List Entry)
    , search : String
    , dbStats : Maybe DbStats
    , currentSearch : Maybe String
    , nResults : Int
    , state : State
    , now : Time.Posix
    , tags : List String
    , selectedTags : Set.Set String
    }


type alias Feed =
    { id : Int
    , title : String
    , details : Maybe FeedDetails
    , isSelected : Bool
    , isVisible : Bool
    , nEntries : Int
    , nResults : Int
    , tags : Set.Set String
    , currentPage : Int
    , endOfFeed : Bool
    }


type alias FeedDetails =
    { id : Int
    , home : String
    , description : String
    , language : String
    , image : String
    , author : String
    , url : String
    }


type alias Entry =
    { id : Int
    , feedid : Int
    , title : String
    , date : Int
    , url : String
    , content : EntryContent
    , isShowingDetails : Bool
    }


type EntryContent
    = EntryBlank
    | EntryWaiting
    | EntryReceived String


type alias DbStats =
    { nPodcasts : Int
    , nEntries : Int
    , dbSize : Int
    }


type State
    = Starting
    | Idle
    | WaitingForResults
    | ShowingResults
    | Error


type Msg
    = InitClock Time.Posix
    | InitState (Result Http.Error Startup)
    | CloseFeed Int
    | AskForEntries Int
    | AskForMoreEntries Int
    | ToggleTag String
    | NewEntries (List NewEntry)
    | NewInput String
    | AskForDetails Int Int
    | NewDetails EntryDetails
    | AskForSearch
    | NewSearchResults (List NewEntry)
    | NewError String
    | NewFeedDetails FeedDetails


type alias Startup =
    { feeds : List InitFeed
    , stats : DbStats
    , tags : List String
    }


type alias InitFeed =
    { id : Int
    , title : String
    , nEntries : Int
    , tags : List String
    }


type alias EntryDetails =
    { id : Int
    , feedid : Int
    , content : String
    }


type alias NewEntry =
    { id : Int
    , feedid : Int
    , title : String
    , date : Int
    , url : String
    }


type alias QuestionEntryDetails =
    { entryId : Int
    , search : String
    }


type alias QueryEntries =
    { feedId : Int
    , page : Int
    , rows : Int
    }


port askForFeedDetails : Int -> Cmd msg


port askForEntryDetails : QuestionEntryDetails -> Cmd msg


port askForEntries : QueryEntries -> Cmd msg


port askForSearch : String -> Cmd msg


port receiveFeedDetails : (FeedDetails -> msg) -> Sub msg


port receiveSearchResults : (List NewEntry -> msg) -> Sub msg


port receiveEntries : (List NewEntry -> msg) -> Sub msg


port receiveEntryDetails : (EntryDetails -> msg) -> Sub msg


port receiveError : (String -> msg) -> Sub msg


init : flags -> ( Model, Cmd Msg )
init _ =
    ( Model [] OrderedDict.empty "" Nothing Nothing 0 Starting (millisToPosix 0) [] Set.empty
    , Cmd.batch
        [ Task.perform InitClock Time.now
        , Http.get
            { url = "./feeds.startup.json"
            , expect = Http.expectJson InitState stateDecoder
            }
        ]
    )


stateDecoder : JD.Decoder Startup
stateDecoder =
    JD.map3 Startup
        (JD.field "feeds"
            (JD.list
                (JD.map4 InitFeed
                    (JD.field "id" JD.int)
                    (JD.field "title" JD.string)
                    (JD.field "nEntries" JD.int)
                    (JD.field "tags" (JD.list JD.string))
                )
            )
        )
        (JD.field "stats"
            (JD.map3 DbStats
                (JD.field "nPodcasts" JD.int)
                (JD.field "nEntries" JD.int)
                (JD.field "dbSize" JD.int)
            )
        )
        (JD.field "tags" (JD.list JD.string))



------------------------------
--          Update
------------------------------


update : Msg -> Model -> ( Model, Cmd msg )
update msg model =
    case msg of
        InitState result ->
            ( updateInitState result model, Cmd.none )

        InitClock n ->
            ( { model | now = n }, Cmd.none )

        NewInput newSearch ->
            ( updateNewInput newSearch model, Cmd.none )

        AskForSearch ->
            updateAskForSearch model

        NewSearchResults es ->
            ( updateNewSearchResults model es, Cmd.none )

        CloseFeed feedId ->
            updateCloseFeed feedId model

        AskForEntries feedId ->
            updateAskForEntries feedId model

        AskForMoreEntries feedId ->
            updateAskForMoreEntries feedId model

        NewEntries es ->
            ( updateNewEntries es model, Cmd.none )

        -- TODO: check if already has details
        AskForDetails feedId entryId ->
            updateAskForDetails feedId entryId model

        NewDetails entryDetails ->
            ( updateNewDetails entryDetails model, Cmd.none )

        NewError _ ->
            ( { model | state = Error }, Cmd.none )

        NewFeedDetails feedDetails ->
            ( updateNewFeedDetails feedDetails model, Cmd.none )

        ToggleTag tag ->
            ( updateToggleTag tag model, Cmd.none )


updateInitState : Result Http.Error Startup -> Model -> Model
updateInitState result model =
    case result of
        Ok startup ->
            { model
                | dbStats = Just startup.stats
                , feeds = List.map toFeed startup.feeds
                , state = Idle
                , tags = List.sort startup.tags
            }

        Err _ ->
            { model | state = Error }


toFeed : InitFeed -> Feed
toFeed { id, title, nEntries, tags } =
    { id = id
    , title = title
    , details = Nothing
    , isSelected = False
    , isVisible = True
    , nEntries = nEntries
    , nResults = 0
    , tags = Set.fromList tags
    , currentPage = 1
    , endOfFeed = False
    }


updateNewInput : String -> Model -> Model
updateNewInput newSearch model =
    if String.isEmpty (String.trim newSearch) then
        let
            updatedFeeds =
                List.map (\feed -> { feed | isVisible = True, isSelected = False, endOfFeed = False, currentPage = 1 })
                    model.feeds
        in
        { model
            | currentSearch = Nothing
            , dbStats = Maybe.map (computeNewStats updatedFeeds Set.empty) model.dbStats
            , entries = OrderedDict.empty
            , feeds = updatedFeeds
            , search = ""
            , selectedTags = Set.empty
            , state = Idle
        }

    else
        { model
            | search = newSearch
            , selectedTags = Set.empty
        }


computeNewStats : List Feed -> Set.Set String -> DbStats -> DbStats
computeNewStats feeds selectedTags stats =
    let
        emptyStats =
            DbStats 0 0 stats.dbSize
    in
    if Set.isEmpty selectedTags then
        List.foldr addFeed emptyStats feeds

    else
        List.foldr addFeedIfVisible emptyStats feeds


addFeed : Feed -> DbStats -> DbStats
addFeed feed ({ nPodcasts, nEntries } as stats) =
    { stats | nPodcasts = nPodcasts + 1, nEntries = nEntries + feed.nEntries }


addFeedIfVisible : Feed -> DbStats -> DbStats
addFeedIfVisible feed ({ nPodcasts, nEntries } as stats) =
    if feed.isVisible then
        { stats | nPodcasts = nPodcasts + 1, nEntries = nEntries + feed.nEntries }

    else
        stats


updateAskForSearch : Model -> ( Model, Cmd msg )
updateAskForSearch model =
    if String.isEmpty (String.trim model.search) then
        ( model, Cmd.none )

    else
        ( { model
            | state = WaitingForResults
            , currentSearch = Just model.search
            , selectedTags = Set.empty
          }
        , askForSearch model.search
        )


updateNewSearchResults : Model -> List NewEntry -> Model
updateNewSearchResults model newEntries =
    let
        feedIds =
            List.foldl (\e -> Set.insert e.feedid) Set.empty newEntries

        feedsCounts =
            List.foldl (\e -> OrderedDict.update e.feedid (Maybe.withDefault 0 >> (+) 1 >> Just))
                OrderedDict.empty
                newEntries

        feeds =
            List.map
                (\feed ->
                    let
                        isMember =
                            Set.member feed.id feedIds
                    in
                    { feed
                        | isSelected = isMember
                        , isVisible = isMember
                        , nResults = Maybe.withDefault 0 <| OrderedDict.get feed.id feedsCounts
                    }
                )
                model.feeds

        entries =
            List.map toEntry newEntries
                |> List.foldl
                    (\entry ->
                        OrderedDict.update entry.feedid
                            (\feedEntries ->
                                case feedEntries of
                                    Nothing ->
                                        Just [ entry ]

                                    Just oldFeedEntries ->
                                        Just (entry :: oldFeedEntries)
                            )
                    )
                    OrderedDict.empty
                |> OrderedDict.map (\_ es -> List.reverse es)
    in
    { model
        | feeds = feeds
        , entries = entries
        , state = ShowingResults
        , nResults = List.sum <| List.map .nResults feeds
    }


updateCloseFeed : Int -> Model -> ( Model, Cmd msg )
updateCloseFeed feedId model =
    ( toggleSelectedFeed model feedId, Cmd.none )


updateAskForEntries : Int -> Model -> ( Model, Cmd msg )
updateAskForEntries feedId model =
    case model.state of
        Idle ->
            ( toggleSelectedFeed model feedId
            , case OrderedDict.get feedId model.entries of
                Nothing ->
                    Cmd.batch
                        [ askForFeedDetails feedId
                        , askForEntries (QueryEntries feedId 0 entriesPerQuery)
                        ]

                Just _ ->
                    askForFeedDetails feedId
            )

        _ ->
            ( toggleSelectedFeed model feedId
            , Cmd.none
            )


updateAskForMoreEntries : Int -> Model -> ( Model, Cmd msg )
updateAskForMoreEntries feedId model =
    let
        mFeed =
            List.Extra.find (\feed -> feed.id == feedId) model.feeds
    in
    case mFeed of
        Just feed ->
            if feed.endOfFeed then
                ( model, Cmd.none )

            else
                ( { model | feeds = nextPageIt model.feeds feedId }
                , askForEntries (QueryEntries feedId feed.currentPage entriesPerQuery)
                )

        Nothing ->
            ( model, Cmd.none )


entriesPerQuery : Int
entriesPerQuery =
    200


nextPageIt : List Feed -> Int -> List Feed
nextPageIt feeds feedId =
    List.Extra.updateIf (\f -> f.id == feedId)
        (\f -> { f | currentPage = f.currentPage + 1 })
        feeds


toggleSelectedFeed : Model -> Int -> Model
toggleSelectedFeed ({ feeds, entries } as model) feedid =
    { model
        | feeds =
            List.map
                (\feed ->
                    if feed.id == feedid then
                        { feed | isSelected = not feed.isSelected }

                    else
                        feed
                )
                feeds
        , entries =
            OrderedDict.update feedid
                (Maybe.map
                    (List.map
                        (\entry ->
                            if entry.isShowingDetails then
                                { entry | isShowingDetails = False }

                            else
                                entry
                        )
                    )
                )
                entries
    }


updateNewEntries : List NewEntry -> Model -> Model
updateNewEntries es model =
    case es of
        [] ->
            model

        -- TODO: getting feedid from newEntries[0] is kind of hacky
        entry :: _ ->
            let
                feeds =
                    List.Extra.updateIf (\feed -> feed.id == entry.feedid)
                        (\feed -> { feed | endOfFeed = List.length es /= entriesPerQuery })
                        model.feeds

                entries =
                    OrderedDict.update entry.feedid (upsertEntries es) model.entries
            in
            { model | entries = entries, feeds = feeds }


upsertEntries : List NewEntry -> Maybe (List Entry) -> Maybe (List Entry)
upsertEntries es mes =
    let
        newEntries =
            List.map toEntry es
    in
    case mes of
        Nothing ->
            Just <| newEntries

        Just olds ->
            Just <| olds ++ newEntries


toEntry : NewEntry -> Entry
toEntry { id, feedid, title, date, url } =
    { id = id
    , feedid = feedid
    , title = title
    , date = date
    , url = url
    , content = EntryBlank
    , isShowingDetails = False
    }


updateAskForDetails : Int -> Int -> Model -> ( Model, Cmd msg )
updateAskForDetails feedId entryId model =
    ( { model | entries = OrderedDict.update feedId (Maybe.map (toggleEntryDetails entryId)) model.entries }
    , askForEntryDetails
        (QuestionEntryDetails entryId <|
            Maybe.withDefault "" model.currentSearch
        )
    )


toggleEntryDetails : Int -> List Entry -> List Entry
toggleEntryDetails entryId =
    List.map
        (\entry ->
            if entry.id == entryId then
                { entry
                    | isShowingDetails = not entry.isShowingDetails
                    , content =
                        if entry.isShowingDetails then
                            EntryBlank

                        else
                            EntryWaiting
                }

            else
                entry
        )


updateNewDetails : EntryDetails -> Model -> Model
updateNewDetails ({ feedid } as entryDetails) model =
    { model | entries = OrderedDict.update feedid (Maybe.map (fillDetails entryDetails)) model.entries }


fillDetails : EntryDetails -> List Entry -> List Entry
fillDetails eDetails =
    List.map
        (\entry ->
            if entry.id == eDetails.id then
                { entry
                    | content =
                        if eDetails.content == "" then
                            EntryReceived "No description."

                        else
                            EntryReceived eDetails.content
                }

            else
                entry
        )


updateNewFeedDetails : FeedDetails -> Model -> Model
updateNewFeedDetails feedDetails model =
    { model
        | feeds =
            List.map
                (\feed ->
                    if feed.id == feedDetails.id && feed.details == Nothing then
                        { feed | details = Just feedDetails }

                    else
                        feed
                )
                model.feeds
    }


updateToggleTag : String -> Model -> Model
updateToggleTag tag model =
    let
        updatedTags =
            toggleSet tag model.selectedTags

        updatedFeeds =
            updateVisibleFeeds updatedTags model.feeds
    in
    { model
        | selectedTags = updatedTags
        , feeds = updatedFeeds
        , dbStats = Maybe.map (computeNewStats updatedFeeds updatedTags) model.dbStats
        , nResults =
            List.sum <|
                List.map .nResults
                    (if Set.isEmpty updatedTags then
                        updatedFeeds

                     else
                        List.filter .isVisible updatedFeeds
                    )
    }


updateVisibleFeeds : Set.Set String -> List Feed -> List Feed
updateVisibleFeeds selectedTags feeds =
    List.map
        (\feed ->
            { feed | isVisible = not (Set.isEmpty (Set.intersect feed.tags selectedTags)) }
        )
        feeds


toggleSet : String -> Set.Set String -> Set.Set String
toggleSet needle hay =
    if Set.member needle hay then
        Set.remove needle hay

    else
        Set.insert needle hay



------------------------------
--          View
------------------------------


view : Model -> Html Msg
view model =
    case model.state of
        Error ->
            div []
                [ viewHeader model
                , viewMain model
                ]

        Starting ->
            div []
                [ viewHeader model
                , viewMain model
                ]

        Idle ->
            div []
                [ viewHeader model
                , viewMain model
                , viewFooter
                ]

        WaitingForResults ->
            div []
                [ viewHeader model
                , viewMain model
                ]

        ShowingResults ->
            div []
                [ viewHeader model
                , viewMain model
                , viewFooter
                ]


viewFooter : Html Msg
viewFooter =
    footer []
        [ a [ href "https://github.com/azimut/newspod" ]
            [ text "source code" ]
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    let
        isStarting =
            model.state == Starting
    in
    header []
        [ div [ class "logo" ]
            [ h1 []
                [ text "news"
                , span [ class "pod" ] [ text "pod" ]
                ]
            , form [ onSubmit AskForSearch ]
                [ input
                    [ type_ "search"
                    , disabled isStarting
                    , placeholder
                        (if isStarting then
                            ""

                         else
                            "search..."
                        )
                    , id "newsearch"
                    , name "newsearch"
                    , value model.search
                    , onInput NewInput
                    , minlength 3
                    , maxlength 30
                    , size 12
                    , autofocus True
                    , autocomplete True
                    ]
                    []
                , button [ type_ "submit", style "display" "none" ] []
                ]
            , viewStatus model
            ]
        , ul [] (liTags model.tags model.selectedTags)
        ]


viewStatus : Model -> Html Msg
viewStatus model =
    case model.state of
        Starting ->
            text ""

        Idle ->
            viewStats model

        Error ->
            div [ class "some-results" ] [ text "ERROR x(" ]

        ShowingResults ->
            case model.nResults of
                0 ->
                    div [ class "some-results" ] [ text "no results found :(" ]

                1 ->
                    div [ class "some-results" ]
                        [ text <| fromInt model.nResults ++ " result found" ]

                _ ->
                    div [ class "some-results" ]
                        [ text <| fromInt model.nResults ++ " results found" ]

        WaitingForResults ->
            div [ class "some-results" ] [ text "..." ]


viewStats : Model -> Html Msg
viewStats { dbStats } =
    case dbStats of
        Nothing ->
            text ""

        Just { nPodcasts, nEntries, dbSize } ->
            div [ class "some-results" ]
                [ div [ class "npodcasts" ] [ text (fromInt nPodcasts ++ " podcasts,") ]
                , div [] [ text (fromInt nEntries ++ " episodes,") ]
                , div [] [ text (Filesize.format dbSize) ]
                ]


liTags : List String -> Set.Set String -> List (Html Msg)
liTags tags selectedTags =
    List.map (liTag selectedTags) tags


liTag : Set.Set String -> String -> Html Msg
liTag selectedTags tag =
    li []
        [ button
            [ btnClass tag selectedTags
            , btnAction tag
            ]
            [ text tag ]
        ]


btnClass : String -> Set.Set String -> Html.Attribute Msg
btnClass tag selectedTags =
    if Set.member tag selectedTags then
        class "enabled"

    else
        class ""


btnAction : String -> Html.Attribute Msg
btnAction tag =
    onClick (ToggleTag tag)


viewMain : Model -> Html Msg
viewMain model =
    main_ [] <|
        case model.state of
            Error ->
                [ text "" ]

            Starting ->
                [ Loaders.ballTriangle 150 "#fff" ]

            Idle ->
                viewFeeds model

            WaitingForResults ->
                [ Loaders.ballTriangle 150 "#fff" ]

            ShowingResults ->
                let
                    filteredFeeds =
                        resultFeeds model

                    feedIds =
                        OrderedDict.keys model.entries |> List.reverse
                in
                List.map
                    (\feed -> viewFeed feed model.state model.now model.entries)
                    (sortFeeds filteredFeeds feedIds [])


viewFeeds : Model -> List (Html Msg)
viewFeeds { feeds, now, entries, state, selectedTags } =
    let
        visibleFeeds =
            if Set.isEmpty selectedTags then
                feeds

            else
                List.filter .isVisible feeds
    in
    List.map (\feed -> viewFeed feed state now entries)
        visibleFeeds


viewFeed : Feed -> State -> Time.Posix -> OrderedDict Int (List Entry) -> Html Msg
viewFeed ({ title, id, isSelected } as feed) state now entries =
    let
        count =
            case state of
                ShowingResults ->
                    feed.nResults

                _ ->
                    feed.nEntries

        content =
            case state of
                Idle ->
                    viewFeedDetails feed :: viewFeedEntries id now entries

                _ ->
                    viewFeedEntries id now entries

        more =
            case state of
                Idle ->
                    if feed.endOfFeed || Maybe.Extra.isNothing feed.details then
                        [ text "" ]

                    else
                        [ div [ class "askformore" ] [ button [ onClick (AskForMoreEntries id) ] [ text "More" ] ] ]

                _ ->
                    [ text "" ]

        action =
            if feed.isSelected then
                CloseFeed id

            else
                AskForEntries id
    in
    article []
        [ details [ open isSelected ] <|
            summary [ onClick action ]
                [ span [] [ text title ]
                , span [] [ text (" [" ++ fromInt count ++ "]") ]
                ]
                :: content
                ++ more
        ]


viewFeedDetails : Feed -> Html Msg
viewFeedDetails { details, isSelected } =
    div
        [ class "episode"
        ]
        [ div [ class "feed-details" ] <|
            case details of
                Nothing ->
                    if isSelected then
                        [ Loaders.ballTriangle 60 "#fff" ]

                    else
                        [ text "..." ]

                Just feedDetails ->
                    [ img [ src feedDetails.image ] []
                    , div [ class "feed-bio" ]
                        [ div [] []
                        , Markdown.toHtml [] feedDetails.description
                        , div [ class "feed-links" ]
                            [ a [ href feedDetails.home ] [ text "Home" ]
                            , a [ href feedDetails.url ] [ text "RSS" ]
                            ]
                        ]
                    ]
        ]


viewFeedEntries : Int -> Time.Posix -> OrderedDict Int (List Entry) -> List (Html Msg)
viewFeedEntries feedId now entries =
    List.map (viewEntry feedId now) <|
        Maybe.withDefault [] (OrderedDict.get feedId entries)


viewEntry : Int -> Time.Posix -> Entry -> Html Msg
viewEntry feedId now entry =
    div
        [ class "episode"

        -- TODO: do not ask when closing...
        , onClickWithStopPropagation (AskForDetails feedId entry.id)
        ]
        [ div [ class "episode-title" ]
            [ text entry.title ]
        , div [ class "episode-date" ]
            [ time [] [ text <| inWords (millisToPosix entry.date) now ]
            , a [ href entry.url ] [ text "Download" ]
            ]
        , div [ class "episode-content" ]
            [ if entry.isShowingDetails then
                case entry.content of
                    EntryBlank ->
                        text ""

                    EntryReceived c ->
                        Markdown.toHtml [] c

                    EntryWaiting ->
                        Loaders.ballTriangle 60 "#fff"

              else
                div [] []
            ]
        ]


onClickWithStopPropagation : msg -> Html.Attribute msg
onClickWithStopPropagation msg =
    stopPropagationOn "click" (JD.map (\m -> ( m, True )) (JD.succeed msg))


open : Bool -> Html.Attribute msg
open flag =
    if flag then
        attribute "open" ""

    else
        class ""


sortFeeds : List Feed -> List Int -> List Feed -> List Feed
sortFeeds feeds ids acc =
    case ids of
        [] ->
            acc

        id :: rest ->
            case List.Extra.find (\feed -> feed.id == id) feeds of
                Nothing ->
                    sortFeeds feeds rest acc

                Just foundFeed ->
                    sortFeeds feeds rest (foundFeed :: acc)


resultFeeds : Model -> List Feed
resultFeeds model =
    if Set.isEmpty model.selectedTags then
        model.feeds

    else
        List.filter .isVisible model.feeds


subscriptions : model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ receiveEntries NewEntries
        , receiveEntryDetails NewDetails
        , receiveSearchResults NewSearchResults
        , receiveError NewError
        , receiveFeedDetails NewFeedDetails
        ]
