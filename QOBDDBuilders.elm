module QOBDDBuilders exposing (..)

--(fromSGToSimpleQOBDD, buildQOBDD)

import Dict exposing (Dict)
import QOBDD exposing (..)
import SimpleGame exposing (..)
import Tuple exposing (first, second)


{-| Binary operations : 0 is and 1 is or
-}
type alias BOP =
    Int


{-| Extracts information from a BDD node
-}
subTreeInfo : BDD -> NodeId
subTreeInfo tree =
    case tree of
        Zero ->
            0

        One ->
            1

        Node nodeData ->
            nodeData.id

        Ref id ->
            id


{-| The type is used to hold specific information about a BDD node
and be used as comparable in a Dict type
-}
type alias NodeInfo =
    ( NodeId, PlayerId, NodeId )


{-| Recursively calls itself to generate a BDD.
-}
buildBDD :
    NodeId
    -> Quota
    -> List PlayerWeight
    -> List Player
    -> Dict NodeInfo BDD
    -> ( BDD, ( NodeId, Dict NodeInfo BDD ) )
buildBDD id quota weights players dict1 =
    case ( weights, players ) of
        ( w :: ws, p :: ps ) ->
            let
                ( lTree, ( lTreeId, dict2 ) ) =
                    buildBDD id (quota - w) ws ps dict1

                ( rTree, ( rTreeId, dict3 ) ) =
                    buildBDD lTreeId quota ws ps dict2

                nodeInfo =
                    ( subTreeInfo lTree
                    , p.id
                    , subTreeInfo rTree
                    )
            in
            case Dict.get nodeInfo dict3 of
                Just refNode ->
                    ( refNode, ( rTreeId, dict3 ) )

                Nothing ->
                    let
                        refNode =
                            Node { id = rTreeId, thenB = lTree, var = p.id, elseB = rTree }
                    in
                    ( refNode
                    , ( rTreeId + 1
                      , Dict.insert nodeInfo refNode dict3
                      )
                    )

        ( _, _ ) ->
            if quota > 0 then
                ( Zero, ( id, dict1 ) )
            else
                ( One, ( id, dict1 ) )


{-| only for BDDs with the same players at the same level
-}
apply : BDD -> BDD -> BOP -> Dict ( NodeId, NodeId, BOP ) BDD -> ( BDD, Dict ( NodeId, NodeId, BOP ) BDD )
apply tree1 tree2 op dict1 =
    case ( tree1, tree2 ) of
        ( Node a, Node b ) ->
            case Dict.get ( a.id, b.id, op ) dict1 of
                Just refNode ->
                    ( refNode, dict1 )

                Nothing ->
                    let
                        ( lBdd, dict2 ) =
                            apply a.thenB b.thenB op dict1

                        ( rBdd, dict3 ) =
                            apply a.elseB b.elseB op dict2

                        refNode =
                            Node { id = a.id, thenB = lBdd, var = a.var, elseB = rBdd }
                    in
                        (refNode, dict3)
        ( Ref _, _ ) ->
            ( Ref 0, dict1 )

        ( _, Ref _ ) ->
            ( Ref 0, dict1 )

        ( sinka, sinkb ) ->
            case ( sinka, sinkb, op ) of
                ( One, One, 0 ) ->
                    ( One, dict1 )

                ( _, _, 0 ) ->
                    ( Zero, dict1 )

                ( Zero, Zero, 1 ) ->
                    ( Zero, dict1 )

                ( _, _, 1 ) ->
                    ( One, dict1 )

                ( _, _, _ ) ->
                    ( Ref 0, dict1 )


{-| Takes a SimpleGame and generates a QOBDD
(at the moment just for the first game rule only)
-}
fromSGToSimpleQOBDD : SimpleGame -> QOBDD
fromSGToSimpleQOBDD game =
    QOBDD game.playerCount
        (case game.rules of
            [] ->
                Zero

            rule :: rules ->
                first (buildBDD 2 rule.quota rule.weights game.players Dict.empty)
        )


joinTree : JoinTree -> List Player -> List RuleMVG -> BDD
joinTree jTree players rules =
    case jTree of
        BoolVar str ->
            case String.toInt str of
                Ok ruleid ->
                    case List.drop (ruleid - 1) rules of
                        r :: rs ->
                            first (buildBDD 2 r.quota r.weights players Dict.empty)

                        _ ->
                            Ref 0

                Err _ ->
                    Ref 0

        BoolAnd tree1 tree2 ->
            case ( joinTree tree1 players rules, joinTree tree2 players rules ) of
                ( left, right ) ->
                    first (apply left right 0 Dict.empty)

        BoolOr tree1 tree2 ->
            case ( joinTree tree1 players rules, joinTree tree2 players rules ) of
                ( left, right ) ->
                    first (apply left right 1 Dict.empty)


buildQOBDD : SimpleGame -> QOBDD
buildQOBDD game =
    case game.joinTree of
        Nothing ->
            fromSGToSimpleQOBDD game

        Just tree ->
            QOBDD game.playerCount (joinTree tree game.players game.rules)
